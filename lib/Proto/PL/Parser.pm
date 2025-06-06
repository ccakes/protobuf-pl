package Proto::PL::Parser;

use strict;
use warnings;
use Carp qw(croak);
use File::Spec;
use File::Basename;
use Proto::PL::AST;

sub new {
    my ($class, %args) = @_;
    return bless {
        include_paths => $args{include_paths} || ['.'],
        parsed_files => {},  # avoid circular imports
        current_file => undef,
        tokens => [],
        pos => 0,
    }, $class;
}

sub parse_file {
    my ($self, $filename) = @_;
    
    # Check if already parsed (avoid cycles)
    return $self->{parsed_files}{$filename} if exists $self->{parsed_files}{$filename};
    
    # Find file in include paths
    my $full_path = $self->_find_file($filename);
    croak "Cannot find file: $filename" unless $full_path;
    
    # Read file content
    open my $fh, '<', $full_path or croak "Cannot read $full_path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # Tokenize
    $self->{tokens} = $self->_tokenize($content);
    $self->{pos} = 0;
    $self->{current_file} = $filename;
    
    # Parse file
    my $file = $self->_parse_file();
    $file->{filename} = $filename;
    
    # Store result
    $self->{parsed_files}{$filename} = $file;
    
    return $file;
}

sub _find_file {
    my ($self, $filename) = @_;
    
    for my $path (@{$self->{include_paths}}) {
        my $full_path = File::Spec->catfile($path, $filename);
        return $full_path if -f $full_path;
    }
    
    return undef;
}

sub _tokenize {
    my ($self, $content) = @_;
    my @tokens;
    
    # Remove comments
    $content =~ s{//.*$}{}gm;
    $content =~ s{/\*.*?\*/}{}gs;
    
    # Tokenize
    while ($content =~ /\G\s*([a-zA-Z_][a-zA-Z0-9_]*|"[^"]*"|'[^']*'|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[{}();=,<>\[\]]|\.)/gc) {
        push @tokens, $1;
    }
    
    return \@tokens;
}

sub _current_token {
    my ($self) = @_;
    return undef if $self->{pos} >= @{$self->{tokens}};
    return $self->{tokens}[$self->{pos}];
}

sub _advance {
    my ($self) = @_;
    $self->{pos}++;
}

sub _expect {
    my ($self, $expected) = @_;
    my $token = $self->_current_token();
    croak "Expected '$expected', got '$token'" unless defined $token && $token eq $expected;
    $self->_advance();
}

sub _parse_file {
    my ($self) = @_;
    my $file = Proto::PL::AST::File->new();
    
    while (defined(my $token = $self->_current_token())) {
        if ($token eq 'syntax') {
            $self->_parse_syntax($file);
        } elsif ($token eq 'package') {
            $self->_parse_package($file);
        } elsif ($token eq 'import') {
            $self->_parse_import($file);
        } elsif ($token eq 'message') {
            push @{$file->{messages}}, $self->_parse_message();
        } elsif ($token eq 'enum') {
            push @{$file->{enums}}, $self->_parse_enum();
        } elsif ($token eq 'option') {
            $self->_parse_file_option($file);
        } else {
            croak "Unexpected token at file level: $token";
        }
    }
    
    return $file;
}

sub _parse_syntax {
    my ($self, $file) = @_;
    $self->_advance();  # consume 'syntax'
    $self->_expect('=');
    my $syntax = $self->_current_token();
    croak "Expected syntax string" unless $syntax =~ /^["'](.+)["']$/;
    $file->{syntax} = $1;
    $self->_advance();
    $self->_expect(';');
}

sub _parse_package {
    my ($self, $file) = @_;
    $self->_advance();  # consume 'package'
    my $package = $self->_parse_dotted_name();
    $file->{package} = $package;
    $self->_expect(';');
}

sub _parse_import {
    my ($self, $file) = @_;
    $self->_advance();  # consume 'import'
    
    # Handle import modifiers (weak, public)
    my $token = $self->_current_token();
    if ($token eq 'weak' || $token eq 'public') {
        $self->_advance();  # consume modifier (ignore for now)
    }
    
    my $import_file = $self->_current_token();
    croak "Expected import filename" unless $import_file =~ /^["'](.+)["']$/;
    push @{$file->{imports}}, $1;
    $self->_advance();
    $self->_expect(';');
}

sub _parse_message {
    my ($self, $parent) = @_;
    $self->_advance();  # consume 'message'
    
    my $name = $self->_current_token();
    croak "Expected message name" unless $name =~ /^[a-zA-Z_]/;
    $self->_advance();
    
    my $message = Proto::PL::AST::Message->new(
        name => $name,
        parent => $parent,
    );
    
    $self->_expect('{');
    
    my $token;
    while (defined($token = $self->_current_token()) && $token ne '}') {
        if ($token eq 'message') {
            my $nested = $self->_parse_message($message);
            push @{$message->{nested_messages}}, $nested;
        } elsif ($token eq 'enum') {
            my $nested = $self->_parse_enum($message);
            push @{$message->{nested_enums}}, $nested;
        } elsif ($token eq 'oneof') {
            my $oneof = $self->_parse_oneof($message);
            push @{$message->{oneofs}}, $oneof;
        } elsif ($token eq 'option') {
            $self->_parse_message_option($message);
        } elsif ($token eq 'reserved') {
            $self->_parse_reserved();  # ignore for now
        } else {
            # Must be a field
            my $field = $self->_parse_field($message);
            push @{$message->{fields}}, $field;
        }
    }
    
    $self->_expect('}');
    return $message;
}

sub _parse_field {
    my ($self, $message) = @_;
    my $label;
    my $token = $self->_current_token();
    
    # Check for field label
    if ($token eq 'optional' || $token eq 'repeated') {
        $label = $token;
        $self->_advance();
        $token = $self->_current_token();
    }
    
    # Parse type
    my $type = $self->_parse_type();
    
    # Parse field name
    my $name = $self->_current_token();
    croak "Expected field name" unless $name =~ /^[a-zA-Z_]/;
    $self->_advance();
    
    # Parse field number
    $self->_expect('=');
    my $number = $self->_current_token();
    croak "Expected field number" unless $number =~ /^\d+$/;
    $self->_advance();
    
    # Validate field number range
    croak "Field number $number out of range (1-536870911)" 
        if $number < 1 || $number > 536870911;
    croak "Field number $number in reserved range (19000-19999)"
        if $number >= 19000 && $number <= 19999;
    
    my $field = Proto::PL::AST::Field->new(
        name => $name,
        number => $number,
        type => $type,
        label => $label,
    );
    
    # Parse options
    if ($self->_current_token() eq '[') {
        $field->{options} = $self->_parse_field_options();
    }
    
    $self->_expect(';');
    return $field;
}

sub _parse_type {
    my ($self) = @_;
    my $token = $self->_current_token();
    
    # Handle map type
    if ($token eq 'map') {
        return $self->_parse_map_type();
    }
    
    # Scalar types
    my %scalar_types = map { $_ => 1 } qw(
        double float int32 int64 uint32 uint64 sint32 sint64
        fixed32 fixed64 sfixed32 sfixed64 bool string bytes
    );
    
    if ($scalar_types{$token}) {
        $self->_advance();
        return Proto::PL::AST::ScalarType->new(name => $token);
    }
    
    # Message or enum type (dotted name)
    my $type_name = $self->_parse_dotted_name();
    
    # For now, we'll resolve these later in the generator
    # This is a placeholder - real implementation would need type resolution
    return Proto::PL::AST::MessageType->new(name => $type_name);
}

sub _parse_map_type {
    my ($self) = @_;
    $self->_advance();  # consume 'map'
    $self->_expect('<');
    
    my $key_type = $self->_parse_type();
    $self->_expect(',');
    my $value_type = $self->_parse_type();
    
    $self->_expect('>');
    
    return Proto::PL::AST::MapType->new(
        key_type => $key_type,
        value_type => $value_type,
    );
}

sub _parse_enum {
    my ($self, $parent) = @_;
    $self->_advance();  # consume 'enum'
    
    my $name = $self->_current_token();
    croak "Expected enum name" unless $name =~ /^[a-zA-Z_]/;
    $self->_advance();
    
    my $enum = Proto::PL::AST::Enum->new(
        name => $name,
        parent => $parent,
    );
    
    $self->_expect('{');
    
    my $token;
    while (defined($token = $self->_current_token()) && $token ne '}') {
        if ($token eq 'option') {
            $self->_parse_enum_option($enum);
        } elsif ($token eq 'reserved') {
            $self->_parse_reserved();  # ignore for now
        } else {
            # Must be an enum value
            my $value = $self->_parse_enum_value();
            push @{$enum->{values}}, $value;
        }
    }
    
    $self->_expect('}');
    return $enum;
}

sub _parse_enum_value {
    my ($self) = @_;
    
    my $name = $self->_current_token();
    croak "Expected enum value name" unless $name =~ /^[a-zA-Z_]/;
    $self->_advance();
    
    $self->_expect('=');
    
    my $number = $self->_current_token();
    croak "Expected enum value number" unless $number =~ /^-?\d+$/;
    $self->_advance();
    
    my $value = Proto::PL::AST::EnumValue->new(
        name => $name,
        number => $number,
    );
    
    # Parse options
    if ($self->_current_token() eq '[') {
        $value->{options} = $self->_parse_field_options();
    }
    
    $self->_expect(';');
    return $value;
}

sub _parse_oneof {
    my ($self, $message) = @_;
    $self->_advance();  # consume 'oneof'
    
    my $name = $self->_current_token();
    croak "Expected oneof name" unless $name =~ /^[a-zA-Z_]/;
    $self->_advance();
    
    my $oneof = Proto::PL::AST::Oneof->new(name => $name);
    
    $self->_expect('{');
    
    my $token;
    while (defined($token = $self->_current_token()) && $token ne '}') {
        if ($token eq 'option') {
            $self->_parse_oneof_option($oneof);
        } else {
            # Must be a field (but without optional/repeated)
            my $field = $self->_parse_field($message);
            $field->{oneof} = $name;
            push @{$oneof->{fields}}, $field;
        }
    }
    
    $self->_expect('}');
    return $oneof;
}

sub _parse_dotted_name {
    my ($self) = @_;
    my @parts;
    
    while (1) {
        my $token = $self->_current_token();
        croak "Expected identifier" unless $token =~ /^[a-zA-Z_]/;
        push @parts, $token;
        $self->_advance();
        
        last unless $self->_current_token() eq '.';
        $self->_advance();  # consume '.'
    }
    
    return join('.', @parts);
}

sub _parse_field_options {
    my ($self) = @_;
    my %options;
    
    $self->_expect('[');
    
    while (1) {
        my $name = $self->_current_token();
        croak "Expected option name" unless $name =~ /^[a-zA-Z_]/;
        $self->_advance();
        
        $self->_expect('=');
        
        my $value = $self->_parse_option_value();
        $options{$name} = $value;
        
        last unless $self->_current_token() eq ',';
        $self->_advance();  # consume ','
    }
    
    $self->_expect(']');
    return \%options;
}

sub _parse_option_value {
    my ($self) = @_;
    my $token = $self->_current_token();
    
    if ($token =~ /^["'](.*)["']$/) {
        # String literal
        $self->_advance();
        return $1;
    } elsif ($token =~ /^-?\d+(?:\.\d+)?$/) {
        # Number
        $self->_advance();
        return $token + 0;  # convert to number
    } elsif ($token =~ /^(true|false)$/) {
        # Boolean
        $self->_advance();
        return $1 eq 'true' ? 1 : 0;
    } elsif ($token =~ /^[a-zA-Z_]/) {
        # Identifier (enum value)
        $self->_advance();
        return $token;
    } else {
        croak "Invalid option value: $token";
    }
}

# Stub methods for options we parse but don't fully implement yet
sub _parse_file_option { shift->_skip_statement() }
sub _parse_message_option { shift->_skip_statement() }
sub _parse_enum_option { shift->_skip_statement() }
sub _parse_oneof_option { shift->_skip_statement() }
sub _parse_reserved { shift->_skip_statement() }

sub _skip_statement {
    my ($self) = @_;
    # Skip until semicolon
    my $token;
    while (defined($token = $self->_current_token()) && $token ne ';') {
        $self->_advance();
    }
    $self->_expect(';') if defined $self->_current_token();
}

1;

__END__

=head1 NAME

Proto::PL::Parser - Protocol Buffers .proto file parser

=head1 SYNOPSIS

    use Proto::PL::Parser;
    
    my $parser = Proto::PL::Parser->new(
        include_paths => ['.', 'protos/'],
    );
    
    my $file = $parser->parse_file('example.proto');

=head1 DESCRIPTION

This module provides a parser for Protocol Buffers .proto files.
It tokenizes the input and builds an Abstract Syntax Tree using
the Proto::PL::AST classes.

=head1 METHODS

=head2 new(%args)

Creates a new parser. Options:

=over 4

=item include_paths - Array of directories to search for imported files

=back

=head2 parse_file($filename)

Parses a .proto file and returns a Proto::PL::AST::File object.

=head1 AUTHOR

Generated by pl_protoc

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
