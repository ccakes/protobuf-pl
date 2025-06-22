package Example::Person;

use strict;
use warnings;
use Proto::PL::Runtime;
use Carp qw(croak);

our @ISA = qw(Proto::PL::Runtime::Message);

use Example::Person::PhoneNumber;
use Example::Person::PhoneType;

use constant FIELD_NAME => 1;
use constant FIELD_ID => 2;
use constant FIELD_EMAIL => 3;
use constant FIELD_PHONES => 4;
use constant FIELD_ATTRIBUTES => 5;
use constant FIELD_IS_ADMIN => 6;
use constant FIELD_PERMISSIONS => 7;

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    
    # Initialize field values
    $self->{phones} = [] unless exists $self->{phones};
    $self->{attributes} = {} unless exists $self->{attributes};
    $self->{permissions} = [] unless exists $self->{permissions};
    $self->{_oneof_permission} = undef unless defined $self->{_oneof_permission};
    
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


sub is_admin {
    my ($self, $value) = @_;
    if (@_ > 1) {
        # Clear other fields in this oneof
        $self->_clear_oneof_except('permission', 'is_admin');
        $self->{is_admin} = $value;
        $self->{_oneof_permission} = 'is_admin';
        return $self;
    }
    return $self->{is_admin};
}

sub permissions {
    my ($self, $value) = @_;
    if (@_ > 1) {
        # Clear other fields in this oneof
        $self->_clear_oneof_except('permission', 'permissions');
        $self->{permissions} = $value;
        $self->{_oneof_permission} = 'permissions';
        return $self;
    }
    return $self->{permissions};
}

sub which_permission {
    my ($self) = @_;
    return $self->{_oneof_permission};
}

sub clear_permission {
    my ($self) = @_;
    if (defined $self->{_oneof_permission}) {
        my $active_field = $self->{_oneof_permission};
        delete $self->{$active_field};
        $self->{_oneof_permission} = undef;
    }
    return $self;
}

sub has_is_admin {
    my ($self) = @_;
    return defined $self->{_oneof_permission} && $self->{_oneof_permission} eq 'is_admin';
}

sub has_permissions {
    my ($self) = @_;
    return defined $self->{_oneof_permission} && $self->{_oneof_permission} eq 'permissions';
}

sub _clear_oneof_except {
    my ($self, $oneof_name, $except_field) = @_;
    return unless defined $self->{"_oneof_${oneof_name}"};
    
    my $current_field = $self->{"_oneof_${oneof_name}"};
    return if $current_field eq $except_field;
    
    # Clear the current field
    delete $self->{$current_field};
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
    
    # Encode repeated field: phones
    if ($self->{phones}) {
        for my $value (@{$self->{phones}}) {
            next unless defined $value;
            $buffer .= Proto::PL::Runtime::_encode_tag(4, 2);
            $buffer .= $value->encode_length_delimited();
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
            
            $buffer .= Proto::PL::Runtime::_encode_tag(5, 2);  # length-delimited
            $buffer .= Proto::PL::Runtime::_encode_varint(length($entry_data));
            $buffer .= $entry_data;
        }
    }
    
    # Encode field: is_admin
    if (defined $self->{_oneof_permission} && $self->{_oneof_permission} eq 'is_admin' && defined $self->{is_admin}) {
        $buffer .= Proto::PL::Runtime::_encode_tag(6, 0);
        $buffer .= Proto::PL::Runtime::_encode_varint($self->{is_admin} ? 1 : 0);
    }
    
    # Encode repeated field: permissions
    if ($self->{permissions}) {
        for my $value (@{$self->{permissions}}) {
            next unless defined $value;
            $buffer .= Proto::PL::Runtime::_encode_tag(7, 2);
            $buffer .= Proto::PL::Runtime::_encode_string($value);
        }
    }
    
    
    return $buffer;
}

sub _decode_field {
    my ($self, $field_num, $wire_type, $value) = @_;
    
    if ($field_num == 1) {
        if ($wire_type == 2) {
            my ($decoded_value, $consumed) = (Proto::PL::Runtime::_decode_string($value), length($value));
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
            my ($decoded_value, $consumed) = (Proto::PL::Runtime::_decode_string($value), length($value));
            $self->{email} = $decoded_value;
            $self->{_present}{email} = 1;
            return 1;
        }
    }
    
    if ($field_num == 4) {
        if ($wire_type == 2) {
            my ($decoded_value, $consumed) = (Example::Person::PhoneNumber->decode($value), length($value));
            push @{$self->{phones}}, $decoded_value;
            return 1;
        }
    }
    
    if ($field_num == 5) {
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
    
    if ($field_num == 6) {
        if ($wire_type == 0) {
            my ($decoded_value, $consumed) = $value, 0;
            $self->_clear_oneof_except('permission', 'is_admin');
            $self->{is_admin} = $decoded_value;
            $self->{_oneof_permission} = 'is_admin';
            $self->{_present}{is_admin} = 1;
            return 1;
        }
    }
    
    if ($field_num == 7) {
        $self->_clear_oneof_except('permission', 'permissions');
        $self->{_oneof_permission} = 'permissions';

        if ($wire_type == 2) {
            my ($decoded_value, $consumed) = (Proto::PL::Runtime::_decode_string($value), length($value));
            push @{$self->{permissions}}, $decoded_value;
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
    $hash->{phones} = $self->{phones} if $self->{phones} && @{$self->{phones}};
    $hash->{attributes} = $self->{attributes} if $self->{attributes} && %{$self->{attributes}};
    $hash->{is_admin} = $self->{is_admin} if defined $self->{_oneof_permission} && $self->{_oneof_permission} eq 'is_admin' && defined $self->{is_admin};
    $hash->{permissions} = $self->{permissions} if $self->{permissions} && @{$self->{permissions}};
}


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
    $msg->phones('phones value');
    $msg->attributes('attributes value');
    $msg->is_admin('is_admin value');
    $msg->permissions('permissions value');
    
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

=head2 phones (repeated message)

=head2 attributes (singular map)

=head2 is_admin (singular scalar, oneof: permission)

=head2 permissions (repeated scalar, oneof: permission)


=head1 ONEOFS

=head2 permission

Fields: is_admin, permissions

Methods: which_permission(), clear_permission(), has_is_admin(), has_permissions()


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


=head2 which_${oneof_name}()

Returns the name of the currently set field in the ${oneof_name} oneof, or undef if none is set.

=head2 clear_${oneof_name}()

Clears all fields in the ${oneof_name} oneof.


=head2 has_${field_name}()

Returns true if ${field_name} is the currently set field in the ${oneof_name} oneof.


=head2 has_${field_name}()

Returns true if ${field_name} is the currently set field in the ${oneof_name} oneof.

=head1 AUTHOR

Generated by pl_protoc

=cut
