package Proto::PL::Runtime;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number blessed);
use List::Util qw(pairs);
use Carp qw(croak);

our $VERSION = '0.01';

# Wire type constants
use constant {
    WIRETYPE_VARINT          => 0,
    WIRETYPE_64BIT           => 1,
    WIRETYPE_LENGTH_DELIMITED => 2,
    WIRETYPE_START_GROUP     => 3,  # deprecated
    WIRETYPE_END_GROUP       => 4,  # deprecated
    WIRETYPE_32BIT           => 5,
};

# Base Message class
package Proto::PL::Runtime::Message;

use strict;
use warnings;
use Scalar::Util qw(blessed);
use Carp qw(croak);

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        _unknown => {},  # unknown fields for round-trip fidelity
        _present => {},  # track presence for optional fields
    }, $class;
    
    # Set provided field values
    for my $field (keys %args) {
        if ($self->can($field)) {
            $self->$field($args{$field});
        } else {
            croak "Unknown field '$field' for $class";
        }
    }
    
    return $self;
}

sub encode {
    my ($self) = @_;
    my $buffer = '';
    
    # Encode known fields (implemented by generated code)
    $buffer .= $self->_encode_fields();
    
    # Encode unknown fields for round-trip fidelity
    for my $field_num (sort { $a <=> $b } keys %{$self->{_unknown}}) {
        for my $value (@{$self->{_unknown}{$field_num}}) {
            $buffer .= $value;
        }
    }
    
    return $buffer;
}

sub encode_length_delimited {
    my ($self) = @_;
    my $encoded = $self->encode();
    
    # Length-delimited encoding: prepend length
    return Proto::PL::Runtime::_encode_varint(length($encoded)) . $encoded;
}

sub decode {
    my ($class, $buffer) = @_;
    my $self = $class->new();
    my $pos = 0;
    my $len = length($buffer);
    
    while ($pos < $len) {
        # Read tag
        my ($tag, $consumed) = Proto::PL::Runtime::_decode_varint($buffer, $pos);
        $pos += $consumed;
        
        my $field_num = $tag >> 3;
        my $wire_type = $tag & 0x07;
        
        # Decode value based on wire type
        my ($value, $value_consumed);
        if ($wire_type == Proto::PL::Runtime::WIRETYPE_VARINT) {
            ($value, $value_consumed) = Proto::PL::Runtime::_decode_varint($buffer, $pos);
        } elsif ($wire_type == Proto::PL::Runtime::WIRETYPE_64BIT) {
            croak "Truncated message: expected 8 bytes" if $pos + 8 > $len;
            $value = substr($buffer, $pos, 8);
            $value_consumed = 8;
        } elsif ($wire_type == Proto::PL::Runtime::WIRETYPE_LENGTH_DELIMITED) {
            my ($length, $len_consumed) = Proto::PL::Runtime::_decode_varint($buffer, $pos);
            $pos += $len_consumed;
            croak "Truncated message: expected $length bytes" if $pos + $length > $len;
            $value = substr($buffer, $pos, $length);
            $value_consumed = $length;
        } elsif ($wire_type == Proto::PL::Runtime::WIRETYPE_32BIT) {
            croak "Truncated message: expected 4 bytes" if $pos + 4 > $len;
            $value = substr($buffer, $pos, 4);
            $value_consumed = 4;
        } elsif ($wire_type == Proto::PL::Runtime::WIRETYPE_START_GROUP) {
            croak "Group wire type not supported (deprecated)";
        } elsif ($wire_type == Proto::PL::Runtime::WIRETYPE_END_GROUP) {
            croak "Group wire type not supported (deprecated)";
        } else {
            croak "Unknown wire type: $wire_type";
        }
        
        $pos += $value_consumed;
        
        # Try to decode field (implemented by generated code)
        if (!$self->_decode_field($field_num, $wire_type, $value)) {
            # Store unknown field
            push @{$self->{_unknown}{$field_num}}, 
                 Proto::PL::Runtime::_encode_tag($field_num, $wire_type) . 
                 ($wire_type == Proto::PL::Runtime::WIRETYPE_VARINT ? 
                  Proto::PL::Runtime::_encode_varint($value) : $value);
        }
    }
    
    return $self;
}

sub to_hash {
    my ($self) = @_;
    my %hash;
    
    # Convert known fields (implemented by generated code)
    $self->_fields_to_hash(\%hash);
    
    return \%hash;
}

sub TO_JSON {
    my ($self) = @_;
    return $self->to_hash;
}

sub from_hash {
    my ($class, $hash) = @_;
    return $class->new(%$hash);
}

# Stub methods to be overridden by generated code
sub _encode_fields { return '' }
sub _decode_field { return 0 }  # return 1 if handled, 0 if unknown
sub _fields_to_hash { }

# Utility functions for wire format encoding/decoding
package Proto::PL::Runtime;

sub _encode_varint {
    my ($value) = @_;
    my $result = '';
    
    while ($value >= 0x80) {
        $result .= chr(($value & 0x7F) | 0x80);
        $value >>= 7;
    }
    $result .= chr($value & 0x7F);
    
    return $result;
}

sub _decode_varint {
    my ($buffer, $pos) = @_;
    my $result = 0;
    my $shift = 0;
    my $len = length($buffer);
    my $consumed = 0;
    
    while ($pos < $len) {
        my $byte = ord(substr($buffer, $pos, 1));
        $pos++;
        $consumed++;
        
        $result |= ($byte & 0x7F) << $shift;
        
        if (($byte & 0x80) == 0) {
            return ($result, $consumed);
        }
        
        $shift += 7;
        croak "Varint too long" if $shift >= 64;
    }
    
    croak "Truncated varint";
}

sub _encode_tag {
    my ($field_num, $wire_type) = @_;
    return _encode_varint(($field_num << 3) | $wire_type);
}

sub _encode_zigzag32 {
    my ($value) = @_;
    return (($value << 1) ^ ($value >> 31)) & 0xFFFFFFFF;
}

sub _decode_zigzag32 {
    my ($value) = @_;
    my $result = (($value >> 1) ^ (-($value & 1))) & 0xFFFFFFFF;
    # Convert to signed
    return $result > 2147483647 ? $result - 4294967296 : $result;
}

sub _encode_zigzag64 {
    my ($value) = @_;
    # Perl handles 64-bit automatically on 64-bit systems
    return ($value << 1) ^ ($value >> 63);
}

sub _decode_zigzag64 {
    my ($value) = @_;
    return ($value >> 1) ^ (-($value & 1));
}

sub _encode_string {
    my ($string) = @_;
    return '' unless defined $string;
    
    # Ensure string is UTF-8 encoded
    utf8::encode($string) if utf8::is_utf8($string);
    
    return _encode_varint(length($string)) . $string;
}

sub _decode_string {
    my ($bytes) = @_;
    
    # Validate UTF-8
    my $string = $bytes;
    if (!utf8::decode($string)) {
        croak "Invalid UTF-8 in string field";
    }
    
    return $string;
}

sub _encode_bytes {
    my ($bytes) = @_;
    return '' unless defined $bytes;
    return _encode_varint(length($bytes)) . $bytes;
}

sub _encode_fixed32 {
    my ($value) = @_;
    return pack('L<', $value);
}

sub _decode_fixed32 {
    my ($bytes) = @_;
    return unpack('L<', $bytes);
}

sub _encode_fixed64 {
    my ($value) = @_;
    return pack('Q<', $value);
}

sub _decode_fixed64 {
    my ($bytes) = @_;
    return unpack('Q<', $bytes);
}

sub _encode_sfixed32 {
    my ($value) = @_;
    return pack('l<', $value);
}

sub _decode_sfixed32 {
    my ($bytes) = @_;
    return unpack('l<', $bytes);
}

sub _encode_sfixed64 {
    my ($value) = @_;
    return pack('q<', $value);
}

sub _decode_sfixed64 {
    my ($bytes) = @_;
    return unpack('q<', $bytes);
}

sub _encode_float {
    my ($value) = @_;
    return pack('f<', $value);
}

sub _decode_float {
    my ($bytes) = @_;
    return unpack('f<', $bytes);
}

sub _encode_double {
    my ($value) = @_;
    return pack('d<', $value);
}

sub _decode_double {
    my ($bytes) = @_;
    return unpack('d<', $bytes);
}

1;

__END__

=head1 NAME

Proto::PL::Runtime - Runtime support for Protocol Buffers in Perl

=head1 SYNOPSIS

    # This module is typically used by generated code
    package MyMessage;
    use parent 'Proto::PL::Runtime::Message';
    
    # Generated accessor methods and encoding/decoding logic would be here

=head1 DESCRIPTION

This module provides the runtime support for Protocol Buffers messages
generated by pl_protoc. It includes the base Message class and utility
functions for encoding and decoding the protobuf wire format.

=head1 WIRE FORMAT

Implements the standard Protocol Buffers wire format with support for:

=over 4

=item * Varint encoding for integers

=item * ZigZag encoding for signed integers  

=item * Fixed 32-bit and 64-bit encoding

=item * Length-delimited encoding for strings, bytes, and messages

=item * Unknown field preservation for round-trip fidelity

=back

=head1 AUTHOR

Generated by pl_protoc

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
