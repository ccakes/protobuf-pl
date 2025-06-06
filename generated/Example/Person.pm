package Example::Person;

use strict;
use warnings;
use Proto::PL::Runtime;
use Carp qw(croak);

our @ISA = qw(Proto::PL::Runtime::Message);

use constant FIELD_NAME => 1;
use constant FIELD_ID => 2;
use constant FIELD_EMAIL => 3;
use constant FIELD_PHONE_NUMBERS => 4;
use constant FIELD_PHONES => 5;
use constant FIELD_ATTRIBUTES => 6;

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    
    # Initialize field values
    $self->{phone_numbers} = [] unless exists $self->{phone_numbers};
    $self->{phones} = [] unless exists $self->{phones};
    $self->{attributes} = {} unless exists $self->{attributes};
    
    return $self;
}

sub name {
    my ($self, $value) = @_;
    
    if (@_ > 1) {
        $self->{name} = $value;
        $self->{_present}{name} = 1;
        return $self;
    }
    
    return $self->{name};
}

sub id {
    my ($self, $value) = @_;
    
    if (@_ > 1) {
        $self->{id} = $value;
        $self->{_present}{id} = 1;
        return $self;
    }
    
    return $self->{id};
}

sub email {
    my ($self, $value) = @_;
    
    if (@_ > 1) {
        $self->{email} = $value;
        $self->{_present}{email} = 1;
        return $self;
    }
    
    return $self->{email};
}

sub phone_numbers {
    my ($self, $value) = @_;
    
    if (@_ > 1) {
        $self->{phone_numbers} = $value;
        $self->{_present}{phone_numbers} = 1;
        return $self;
    }
    
    return $self->{phone_numbers};
}

sub phones {
    my ($self, $value) = @_;
    
    if (@_ > 1) {
        $self->{phones} = $value;
        $self->{_present}{phones} = 1;
        return $self;
    }
    
    return $self->{phones};
}

sub attributes {
    my ($self, $value) = @_;
    
    if (@_ > 1) {
        $self->{attributes} = $value;
        $self->{_present}{attributes} = 1;
        return $self;
    }
    
    return $self->{attributes};
}

sub _encode_fields {
    my ($self) = @_;
    my $buffer = '';
    
    # Encode field: name
    if (defined $self->{name}) {
        $buffer .= Proto::PL::Runtime::_encode_tag(1, 2);
        $buffer .= Proto::PL::Runtime::_encode_string($self->{name});
    }
    
    # Encode field: id
    if (defined $self->{id}) {
        $buffer .= Proto::PL::Runtime::_encode_tag(2, 0);
        $buffer .= Proto::PL::Runtime::_encode_varint($self->{id});
    }
    
    # Encode field: email
    if (exists $self->{_present}{email} && defined $self->{email}) {
        $buffer .= Proto::PL::Runtime::_encode_tag(3, 2);
        $buffer .= Proto::PL::Runtime::_encode_string($self->{email});
    }
    
    # Encode repeated field: phone_numbers
    if ($self->{phone_numbers}) {
        for my $value (@{$self->{phone_numbers}}) {
            next unless defined $value;
            $buffer .= Proto::PL::Runtime::_encode_tag(4, 2);
            $buffer .= Proto::PL::Runtime::_encode_string($value);
        }
    }
    
    # Encode repeated field: phones
    if ($self->{phones}) {
        for my $value (@{$self->{phones}}) {
            next unless defined $value;
            $buffer .= Proto::PL::Runtime::_encode_tag(5, 2);
            $buffer .= $value->encode();
        }
    }
    
    # Encode map field: attributes
    if ($self->{attributes}) {
        for my $key (keys %{$self->{attributes}}) {
            my $value = $self->{attributes}{$key};
            my $entry_data = '';
            
            # Key (field 1)
            $entry_data .= Proto::PL::Runtime::_encode_tag(1, 2);
            $entry_data .= Proto::PL::Runtime::_encode_string($key);
            
            # Value (field 2)
            if (defined $value) {
                $entry_data .= Proto::PL::Runtime::_encode_tag(2, 2);
                $entry_data .= Proto::PL::Runtime::_encode_string($value);
            }
            
            $buffer .= Proto::PL::Runtime::_encode_tag(6, 2);  # length-delimited
            $buffer .= Proto::PL::Runtime::_encode_varint(length($entry_data));
            $buffer .= $entry_data;
        }
    }
    
    
    return $buffer;
}

sub _decode_field {
    my ($self, $field_num, $wire_type, $value) = @_;
    
    if ($field_num == 1) {
        if ($wire_type == 2) {
            my ($decoded_value, $consumed) = Proto::PL::Runtime::_decode_string($value), length($value);
            $self->{name} = $decoded_value;
            $self->{_present}{name} = 1;
            return 1;
        }
    }
    
    if ($field_num == 2) {
        if ($wire_type == 0) {
            my ($decoded_value, $consumed) = $value, 0;
            $self->{id} = $decoded_value;
            $self->{_present}{id} = 1;
            return 1;
        }
    }
    
    if ($field_num == 3) {
        if ($wire_type == 2) {
            my ($decoded_value, $consumed) = Proto::PL::Runtime::_decode_string($value), length($value);
            $self->{email} = $decoded_value;
            $self->{_present}{email} = 1;
            return 1;
        }
    }
    
    if ($field_num == 4) {
        if ($wire_type == 2) {
            my ($decoded_value, $consumed) = Proto::PL::Runtime::_decode_string($value), length($value);
            push @{$self->{phone_numbers}}, $decoded_value;
            return 1;
        }
    }
    
    if ($field_num == 5) {
        if ($wire_type == 2) {
            my ($decoded_value, $consumed) = PhoneNumber->decode($value), length($value);
            push @{$self->{phones}}, $decoded_value;
            return 1;
        }
    }
    
    if ($field_num == 6) {
        if ($wire_type == 2) {  # length-delimited (map entry)
            my $pos = 0;
            my $len = length($value);
            my ($key, $map_value);
            
            while ($pos < $len) {
                my ($tag, $tag_consumed) = Proto::PL::Runtime::_decode_varint($value, $pos);
                $pos += $tag_consumed;
                
                my $entry_field_num = $tag >> 3;
                my $entry_wire_type = $tag & 0x07;
                
                if ($entry_field_num == 1) {  # Key
                    ($key, my $key_consumed) = do { my ($len, $len_consumed) = Proto::PL::Runtime::_decode_varint($value, $pos); my $bytes = substr($value, $pos + $len_consumed, $len); (Proto::PL::Runtime::_decode_string($bytes), $len_consumed + $len) };
                    $pos += $key_consumed;
                } elsif ($entry_field_num == 2) {  # Value
                    ($map_value, my $value_consumed) = do { my ($len, $len_consumed) = Proto::PL::Runtime::_decode_varint($value, $pos); my $bytes = substr($value, $pos + $len_consumed, $len); (Proto::PL::Runtime::_decode_string($bytes), $len_consumed + $len) };
                    $pos += $value_consumed;
                } else {
                    # Skip unknown field in map entry
                    if ($entry_wire_type == 0) {
                        my ($skip_value, $skip_consumed) = Proto::PL::Runtime::_decode_varint($value, $pos);
                        $pos += $skip_consumed;
                    } elsif ($entry_wire_type == 1) {
                        $pos += 8;
                    } elsif ($entry_wire_type == 2) {
                        my ($skip_len, $len_consumed) = Proto::PL::Runtime::_decode_varint($value, $pos);
                        $pos += $len_consumed + $skip_len;
                    } elsif ($entry_wire_type == 5) {
                        $pos += 4;
                    }
                }
            }
            
            $self->{attributes}{$key} = $map_value if defined $key;
            return 1;
        }
    }
    
    
    return 0;  # Unknown field
}

sub _fields_to_hash {
    my ($self, $hash) = @_;
    
    $hash->{name} = $self->{name} if defined $self->{name};
    $hash->{id} = $self->{id} if defined $self->{id};
    $hash->{email} = $self->{email} if exists $self->{_present}{email} && defined $self->{email};
    $hash->{phone_numbers} = $self->{phone_numbers} if $self->{phone_numbers} && @{$self->{phone_numbers}};
    $hash->{phones} = $self->{phones} if $self->{phones} && @{$self->{phones}};
    $hash->{attributes} = $self->{attributes} if $self->{attributes} && %{$self->{attributes}};
}


package Example::Person::PhoneNumber;
our @ISA = qw(Proto::PL::Runtime::Message);

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    
    # Initialize field values
    
    return $self;
}

sub number {
    my ($self, $value) = @_;
    
    if (@_ > 1) {
        $self->{number} = $value;
        $self->{_present}{number} = 1;
        return $self;
    }
    
    return $self->{number};
}

sub type {
    my ($self, $value) = @_;
    
    if (@_ > 1) {
        $self->{type} = $value;
        $self->{_present}{type} = 1;
        return $self;
    }
    
    return $self->{type};
}

sub _encode_fields {
    my ($self) = @_;
    my $buffer = '';
    
    # Encode field: number
    if (defined $self->{number}) {
        $buffer .= Proto::PL::Runtime::_encode_tag(1, 2);
        $buffer .= Proto::PL::Runtime::_encode_string($self->{number});
    }
    
    # Encode field: type
    if (defined $self->{type}) {
        $buffer .= Proto::PL::Runtime::_encode_tag(2, 2);
        $buffer .= $self->{type}->encode();
    }
    
    
    return $buffer;
}

sub _decode_field {
    my ($self, $field_num, $wire_type, $value) = @_;
    
    if ($field_num == 1) {
        if ($wire_type == 2) {
            my ($decoded_value, $consumed) = Proto::PL::Runtime::_decode_string($value), length($value);
            $self->{number} = $decoded_value;
            $self->{_present}{number} = 1;
            return 1;
        }
    }
    
    if ($field_num == 2) {
        if ($wire_type == 2) {
            my ($decoded_value, $consumed) = PhoneType->decode($value), length($value);
            $self->{type} = $decoded_value;
            $self->{_present}{type} = 1;
            return 1;
        }
    }
    
    
    return 0;  # Unknown field
}

sub _fields_to_hash {
    my ($self, $hash) = @_;
    
    $hash->{number} = $self->{number} if defined $self->{number};
    $hash->{type} = $self->{type} if defined $self->{type};
}


package Example::Person::PhoneType;

use constant {
    MOBILE => 0,
    HOME => 1,
    WORK => 2,
};


1;

__END__

=head1 NAME

Example::Person - Protocol Buffers message class

=head1 SYNOPSIS

    use Example::Person;
    
    my $msg = Example::Person->new();
    
    # Set fields
    $msg->name('name value');
    $msg->id('id value');
    $msg->email('email value');
    $msg->phone_numbers('phone_numbers value');
    $msg->phones('phones value');
    $msg->attributes('attributes value');
    
    # Encode to bytes
    my $bytes = $msg->encode();
    
    # Decode from bytes
    my $decoded = ${package_name}->decode($bytes);

=head1 DESCRIPTION

This class represents a Protocol Buffers message.

=head1 FIELDS

=head2 name (singular scalar)

=head2 id (singular scalar)

=head2 email (optional scalar)

=head2 phone_numbers (repeated scalar)

=head2 phones (repeated message)

=head2 attributes (singular map)


=head1 METHODS

=head2 new(%args)

Constructor. Field names can be provided as arguments.

=head2 encode()

Encodes the message to Protocol Buffers wire format.

=head2 decode($bytes)

Class method that decodes bytes in Protocol Buffers wire format.

=head2 to_hash()

Returns a hash representation of the message.

=head2 from_hash($hashref)

Class method that creates a message from a hash.

=head1 AUTHOR

Generated by pl_protoc

=cut
