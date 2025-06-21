package Proto::PL::Generator;

use strict;
use warnings;
use Carp       qw(croak);
use File::Path qw(make_path);
use File::Spec;
use Proto::PL::AST;

sub new {
  my ($class, %args) = @_;
  return bless {
    output_dir => $args{output_dir} || 'lib',
    files      => {},                           # file AST objects by filename
  }, $class;
}

sub add_file {
  my ($self, $file) = @_;
  $self->{files}{$file->filename} = $file;
}

sub generate_all {
  my ($self) = @_;

  for my $filename (keys %{$self->{files}}) {
    my $file = $self->{files}{$filename};
    $self->generate_file($file);
  }
}

# Borrowed from https://metacpan.org/pod/String::CamelCase
sub _camelize {
  my ($string) = @_;

  return lcfirst(join('', map { ucfirst $_ } split(/(?<=[A-Za-z])_(?=[A-Za-z])|\b/, $string)));
}

sub generate_file {
  my ($self, $file) = @_;

  # Determine output file path
  my $package       = $file->package || '';
  my @package_parts = split /\./, $package;
  map { $_ = _camelize($_); s/^(.)/uc($1)/e } @package_parts;    # Capitalize each part

  my $output_path = File::Spec->catfile($self->{output_dir}, @package_parts);

  make_path($output_path) if @package_parts;

  # Generate code for each top-level message and enum
  for my $message (@{$file->messages}) {
    $self->_generate_message_file($message, $file, $output_path);
  }

  for my $enum (@{$file->enums}) {
    $self->_generate_enum_file($enum, $file, $output_path);
  }
} ## end sub generate_file

sub _generate_message_file {
  my ($self, $message, $file, $output_path) = @_;

  my $package_prefix = $self->_get_package_prefix($file);
  my $filename       = File::Spec->catfile($output_path, $message->name . '.pm');

  my $code = $self->_generate_message_code($message, $package_prefix, $file);

  # Write to file
  open my $fh, '>', $filename or croak "Cannot write $filename: $!";
  print $fh $code;
  close $fh;
}

sub _generate_enum_file {
  my ($self, $enum, $file, $output_path) = @_;

  my $package_prefix = $self->_get_package_prefix($file);
  my $filename       = File::Spec->catfile($output_path, $enum->name . '.pm');

  my $code = $self->_generate_enum_code($enum, $package_prefix);

  # Write to file
  open my $fh, '>', $filename or croak "Cannot write $filename: $!";
  print $fh $code;
  close $fh;
}

sub _get_package_prefix {
  my ($self, $file) = @_;
  return '' unless $file->package;

  my $package = _camelize($file->package);
  $package =~ s/\./::/g;
  $package =~ s/^(.)/uc($1)/e;    # Capitalize first letter
                                  # $package =~ s/::(.)/::uc($1)/ge;    # Capitalize after ::

  return $package;
}

sub _generate_message_code {
  my ($self, $message, $package_prefix, $file) = @_;

  my $package_name = $message->perl_package_name($package_prefix);

  my $code = <<EOF;
package ${package_name};

use strict;
use warnings;
use Proto::PL::Runtime;
use Carp qw(croak);

our \@ISA = qw(Proto::PL::Runtime::Message);

EOF

  # Generate field constants
  my %field_numbers = map { $_->name => $_->number } @{$message->fields};
  for my $field (@{$message->fields}) {
    $code .= sprintf("use constant FIELD_%s => %d;\n", uc($field->name), $field->number);
  }
  $code .= "\n";

  # Generate constructor
  $code .= $self->_generate_constructor($message);

  # Generate field accessors
  for my $field (@{$message->fields}) {
    $code .= $self->_generate_field_accessor($field);
  }

  # Generate oneof accessors and methods
  for my $oneof (@{$message->oneofs}) {
    $code .= $self->_generate_oneof_methods($oneof);
  }

  # Generate helper methods
  $code .= $self->_generate_helper_methods($message);

  # Generate encoding method
  $code .= $self->_generate_encode_method($message, $file);

  # Generate decoding method
  $code .= $self->_generate_decode_method($message, $file);

  # Generate hash conversion methods
  $code .= $self->_generate_hash_methods($message);

  # Generate nested messages and enums in the same file
  for my $nested (@{$message->nested_messages}) {
    $code .= "\n" . $self->_generate_nested_message_code($nested, $package_name, $file);
  }

  for my $nested (@{$message->nested_enums}) {
    $code .= "\n" . $self->_generate_nested_enum_code($nested, $package_name);
  }

  $code .= "\n1;\n\n";
  $code .= $self->_generate_pod_documentation($message, $package_name);

  return $code;
} ## end sub _generate_message_code

sub _generate_constructor {
  my ($self, $message) = @_;

  my $code = <<'EOF';
sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    
    # Initialize field values
EOF

  for my $field (@{$message->fields}) {
    if ($field->is_map) {
      $code .= sprintf("    \$self->{%s} = {} unless exists \$self->{%s};\n", $field->name, $field->name);
    }
    elsif ($field->is_repeated) {
      $code .= sprintf("    \$self->{%s} = [] unless exists \$self->{%s};\n", $field->name, $field->name);
    }
  }

  # Initialize oneof tracking (only if not already set by constructor args)
  for my $oneof (@{$message->oneofs}) {
    $code .= sprintf("    \$self->{_oneof_%s} = undef unless defined \$self->{_oneof_%s};\n", $oneof->name, $oneof->name);
  }

  $code .= <<'EOF';
    
    return $self;
}

EOF

  return $code;
} ## end sub _generate_constructor

sub _generate_field_accessor {
  my ($self, $field) = @_;

  my $name = $field->name;

  # Check if this field is part of a oneof
  if ($field->oneof) {
    return $self->_generate_oneof_field_accessor($field);
  }

  my $code = <<EOF;
sub ${name} {
    my (\$self, \$value) = \@_;
    
    if (\@_ > 1) {
        \$self->{${name}} = \$value;
        \$self->{_present}{${name}} = 1;
        return \$self;
    }
    
    return \$self->{${name}};
}

EOF

  return $code;
} ## end sub _generate_field_accessor

sub _generate_oneof_field_accessor {
  my ($self, $field) = @_;
  my $name       = $field->name;
  my $oneof_name = $field->oneof;

  my $code = <<EOF;

sub ${name} {
    my (\$self, \$value) = \@_;
    if (\@_ > 1) {
        # Clear other fields in this oneof
        \$self->_clear_oneof_except('${oneof_name}', '${name}');
        \$self->{${name}} = \$value;
        \$self->{_oneof_${oneof_name}} = '${name}';
        return \$self;
    }
    return \$self->{${name}};
}
EOF

  return $code;
} ## end sub _generate_oneof_field_accessor

sub _generate_oneof_methods {
  my ($self, $oneof) = @_;
  my $oneof_name  = $oneof->name;
  my @field_names = map { $_->name } @{$oneof->fields};

  my $code = <<EOF;

sub which_${oneof_name} {
    my (\$self) = \@_;
    return \$self->{_oneof_${oneof_name}};
}

sub clear_${oneof_name} {
    my (\$self) = \@_;
    if (defined \$self->{_oneof_${oneof_name}}) {
        my \$active_field = \$self->{_oneof_${oneof_name}};
        delete \$self->{\$active_field};
        \$self->{_oneof_${oneof_name}} = undef;
    }
    return \$self;
}
EOF

  # Generate has_field methods for each field in the oneof
  for my $field_name (@field_names) {
    $code .= <<EOF;

sub has_${field_name} {
    my (\$self) = \@_;
    return defined \$self->{_oneof_${oneof_name}} && \$self->{_oneof_${oneof_name}} eq '${field_name}';
}
EOF
  }

  return $code;
} ## end sub _generate_oneof_methods

sub _generate_helper_methods {
  my ($self, $message) = @_;
  my $code = '';

  # Generate _clear_oneof_except helper if there are oneofs
  if (@{$message->oneofs}) {
    $code .= <<'EOF';

sub _clear_oneof_except {
    my ($self, $oneof_name, $except_field) = @_;
    return unless defined $self->{"_oneof_${oneof_name}"};
    
    my $current_field = $self->{"_oneof_${oneof_name}"};
    return if $current_field eq $except_field;
    
    # Clear the current field
    delete $self->{$current_field};
}
EOF
  }

  return $code;
} ## end sub _generate_helper_methods

sub _generate_encode_method {
  my ($self, $message, $file) = @_;

  my $code = <<'EOF';
sub _encode_fields {
    my ($self) = @_;
    my $buffer = '';
    
EOF

  for my $field (@{$message->fields}) {
    $code .= $self->_generate_field_encoding($field, $file);
  }

  $code .= <<'EOF';
    
    return $buffer;
}

EOF

  return $code;
} ## end sub _generate_encode_method

sub _generate_field_encoding {
  my ($self, $field, $file) = @_;

  # Resolve the field type properly
  my $resolved_type  = $self->_resolve_field_type($field, $file);
  my $resolved_field = Proto::PL::AST::Field->new(
    name    => $field->name,
    number  => $field->number,
    type    => $resolved_type,
    label   => $field->label,
    options => $field->options,
    oneof   => $field->oneof,
  );

  my $name   = $resolved_field->name;
  my $number = $resolved_field->number;
  my $code   = "";

  if ($field->is_repeated) {
    if ($field->is_packed) {

      # Packed repeated field
      $code .= <<EOF;
    # Encode packed repeated field: ${name}
    if (\$self->{${name}} && \@{\$self->{${name}}}) {
        my \$packed_data = '';
        for my \$value (\@{\$self->{${name}}}) {
            \$packed_data .= ${\ $self->_get_encode_expression($field, '$value') };
        }
        \$buffer .= Proto::PL::Runtime::_encode_tag(${number}, 2);  # length-delimited
        \$buffer .= Proto::PL::Runtime::_encode_varint(length(\$packed_data));
        \$buffer .= \$packed_data;
    }
    
EOF
    }
    else {
      # Regular repeated field
      $code .= <<EOF;
    # Encode repeated field: ${name}
    if (\$self->{${name}}) {
        for my \$value (\@{\$self->{${name}}}) {
            next unless defined \$value;
            \$buffer .= Proto::PL::Runtime::_encode_tag(${number}, ${\$field->wire_type});
            \$buffer .= ${\ $self->_get_encode_expression($field, '$value') };
        }
    }
    
EOF
    }
  } ## end if ($field->is_repeated)
  elsif ($field->is_map) {

    # Map field
    $code .= <<EOF;
    # Encode map field: ${name}
    if (\$self->{${name}}) {
        for my \$key (keys \%{\$self->{${name}}}) {
            my \$value = \$self->{${name}}{\$key};
            my \$entry_data = '';
            
            # Key (field 1)
            \$entry_data .= Proto::PL::Runtime::_encode_tag(1, ${\$field->type->key_type->wire_type});
            \$entry_data .= ${\ $self->_get_encode_expression_for_type($field->type->key_type, '$key') };
            
            # Value (field 2)
            if (defined \$value) {
                \$entry_data .= Proto::PL::Runtime::_encode_tag(2, ${\$field->type->value_type->wire_type});
                \$entry_data .= ${\ $self->_get_encode_expression_for_type($field->type->value_type, '$value') };
            }
            
            \$buffer .= Proto::PL::Runtime::_encode_tag(${number}, 2);  # length-delimited
            \$buffer .= Proto::PL::Runtime::_encode_varint(length(\$entry_data));
            \$buffer .= \$entry_data;
        }
    }
    
EOF
  } ## end elsif ($field->is_map)
  else {
    # Singular field
    my $presence_check;

    if ($field->oneof) {

      # Oneof field - only encode if this field is the active one in the oneof
      my $oneof_name = $field->oneof;
      $presence_check = "defined \$self->{_oneof_${oneof_name}} && \$self->{_oneof_${oneof_name}} eq '${name}' && ";
    }
    elsif ($field->is_optional) {
      $presence_check = "exists \$self->{_present}{${name}} && ";
    }
    else {
      $presence_check = "";
    }

    my $wire_type = $resolved_field->type->wire_type;

    $code .= <<EOF;
    # Encode field: ${name}
    if (${presence_check}defined \$self->{${name}}) {
        \$buffer .= Proto::PL::Runtime::_encode_tag(${number}, ${wire_type});
        \$buffer .= ${\ $self->_get_encode_expression($resolved_field, "\$self->{${name}}") };
    }
    
EOF
  } ## end else [ if ($field->is_repeated)]

  return $code;
} ## end sub _generate_field_encoding

sub _get_encode_expression {
  my ($self, $field, $var) = @_;
  return $self->_get_encode_expression_for_type($field->type, $var);
}

sub _get_encode_expression_for_type {
  my ($self, $type, $var) = @_;

  if ($type->isa('Proto::PL::AST::ScalarType')) {
    my $type_name = $type->name;

    if ($type_name eq 'string') {
      return "Proto::PL::Runtime::_encode_string(${var})";
    }
    elsif ($type_name eq 'bytes') {
      return "Proto::PL::Runtime::_encode_bytes(${var})";
    }
    elsif ($type_name eq 'bool') {
      return "Proto::PL::Runtime::_encode_varint(${var} ? 1 : 0)";
    }
    elsif ($type_name =~ /^sint/) {
      my $zigzag_func = $type_name eq 'sint32' ? '_encode_zigzag32' : '_encode_zigzag64';
      return "Proto::PL::Runtime::_encode_varint(Proto::PL::Runtime::${zigzag_func}(${var}))";
    }
    elsif ($type_name =~ /^(int|uint)/) {
      return "Proto::PL::Runtime::_encode_varint(${var})";
    }
    elsif ($type_name eq 'fixed32') {
      return "Proto::PL::Runtime::_encode_fixed32(${var})";
    }
    elsif ($type_name eq 'fixed64') {
      return "Proto::PL::Runtime::_encode_fixed64(${var})";
    }
    elsif ($type_name eq 'sfixed32') {
      return "Proto::PL::Runtime::_encode_sfixed32(${var})";
    }
    elsif ($type_name eq 'sfixed64') {
      return "Proto::PL::Runtime::_encode_sfixed64(${var})";
    }
    elsif ($type_name eq 'float') {
      return "Proto::PL::Runtime::_encode_float(${var})";
    }
    elsif ($type_name eq 'double') {
      return "Proto::PL::Runtime::_encode_double(${var})";
    }
  } ## end if ($type->isa('Proto::PL::AST::ScalarType'...))
  elsif ($type->isa('Proto::PL::AST::EnumType')) {
    return "Proto::PL::Runtime::_encode_varint(${var})";
  }
  elsif ($type->isa('Proto::PL::AST::MessageType')) {
    return "${var}->encode_length_delimited()";
  }

  croak "Unknown type for encoding: " . ref($type);
} ## end sub _get_encode_expression_for_type

sub _generate_decode_method {
  my ($self, $message, $file) = @_;

  my $code = <<'EOF';
sub _decode_field {
    my ($self, $field_num, $wire_type, $value) = @_;
    
EOF

  for my $field (@{$message->fields}) {
    $code .= $self->_generate_field_decoding($field, $file);
  }

  $code .= <<'EOF';
    
    return 0;  # Unknown field
}

EOF

  return $code;
} ## end sub _generate_decode_method

sub _generate_field_decoding {
  my ($self, $field, $file) = @_;

  # Resolve the field type properly
  my $resolved_type  = $self->_resolve_field_type($field, $file);
  my $resolved_field = Proto::PL::AST::Field->new(
    name    => $field->name,
    number  => $field->number,
    type    => $resolved_type,
    label   => $field->label,
    options => $field->options,
    oneof   => $field->oneof,
  );

  my $name               = $resolved_field->name;
  my $number             = $resolved_field->number;
  my $expected_wire_type = $resolved_field->wire_type;

  my $code = <<EOF;
    if (\$field_num == ${number}) {
EOF

  if ($resolved_field->is_repeated) {
    if ($resolved_field->oneof) {

      # Oneof field - clear other fields in the oneof and set this one
      my $oneof_name = $resolved_field->oneof;
      $code .= <<EOF;
        \$self->_clear_oneof_except('${oneof_name}', '${name}');
        \$self->{_oneof_${oneof_name}} = '${name}';

EOF
    }

    if ($resolved_field->is_packed) {

      # Packed repeated field
      $code .= <<EOF;
        if (\$wire_type == 2) {  # length-delimited (packed)
            my \$pos = 0;
            my \$len = length(\$value);
            while (\$pos < \$len) {
                my (\$decoded_value, \$consumed) = ${\ $self->_get_decode_expression($file, $resolved_field, '$value', '$pos') };
                push \@{\$self->{${name}}}, \$decoded_value;
                \$pos += \$consumed;
            }
            return 1;
        } elsif (\$wire_type == ${expected_wire_type}) {  # individual value
            my (\$decoded_value, \$consumed) = ${\ $self->_get_decode_expression($file, $resolved_field, '$value', '0') };
            push \@{\$self->{${name}}}, \$decoded_value;
            return 1;
        }
EOF
    } ## end if ($resolved_field->is_packed)
    else {

      # Regular repeated field
      $code .= <<EOF;
        if (\$wire_type == ${expected_wire_type}) {
            my (\$decoded_value, \$consumed) = ${\ $self->_get_decode_expression($file, $resolved_field, '$value', '0') };
            push \@{\$self->{${name}}}, \$decoded_value;
            return 1;
        }
EOF
    }
  } ## end if ($resolved_field->is_repeated)
  elsif ($resolved_field->is_map) {

    # Map field
    $code .= <<EOF;
        if (\$wire_type == 2) {  # length-delimited (map entry)
            my \$pos = 0;
            my \$len = length(\$value);
            my (\$key, \$map_value);
            
            while (\$pos < \$len) {
                my (\$tag, \$tag_consumed) = Proto::PL::Runtime::_decode_varint(\$value, \$pos);
                \$pos += \$tag_consumed;
                
                my \$entry_field_num = \$tag >> 3;
                my \$entry_wire_type = \$tag & 0x07;
                
                if (\$entry_field_num == 1) {  # Key
                    (\$key, my \$key_consumed) = ${\ $self->_get_decode_expression_for_type($file, $resolved_field->type->key_type, '$value', '$pos') };
                    \$pos += \$key_consumed;
                } elsif (\$entry_field_num == 2) {  # Value
                    (\$map_value, my \$value_consumed) = ${\ $self->_get_decode_expression_for_type($file, $resolved_field->type->value_type, '$value', '$pos') };
                    \$pos += \$value_consumed;
                } else {
                    # Skip unknown field in map entry
                    if (\$entry_wire_type == 0) {
                        my (\$skip_value, \$skip_consumed) = Proto::PL::Runtime::_decode_varint(\$value, \$pos);
                        \$pos += \$skip_consumed;
                    } elsif (\$entry_wire_type == 1) {
                        \$pos += 8;
                    } elsif (\$entry_wire_type == 2) {
                        my (\$skip_len, \$len_consumed) = Proto::PL::Runtime::_decode_varint(\$value, \$pos);
                        \$pos += \$len_consumed + \$skip_len;
                    } elsif (\$entry_wire_type == 5) {
                        \$pos += 4;
                    }
                }
            }
            
            \$self->{${name}}{\$key} = \$map_value if defined \$key;
            return 1;
        }
EOF
  } ## end elsif ($resolved_field->is_map)
  else {
    # Singular field
    $code .= <<EOF;
        if (\$wire_type == ${expected_wire_type}) {
            my (\$decoded_value, \$consumed) = ${\ $self->_get_decode_expression($file, $resolved_field, '$value', '0') };
EOF

    if ($resolved_field->oneof) {

      # Oneof field - clear other fields in the oneof and set this one
      my $oneof_name = $resolved_field->oneof;
      $code .= <<EOF;
            \$self->_clear_oneof_except('${oneof_name}', '${name}');
            \$self->{${name}} = \$decoded_value;
            \$self->{_oneof_${oneof_name}} = '${name}';
EOF
    }
    else {
      # Regular singular field
      $code .= <<EOF;
            \$self->{${name}} = \$decoded_value;
EOF
    }

    $code .= <<EOF;
            \$self->{_present}{${name}} = 1;
            return 1;
        }
EOF
  } ## end else [ if ($resolved_field->is_repeated)]

  $code .= "    }\n    \n";

  return $code;
} ## end sub _generate_field_decoding

sub _get_decode_expression {
  my ($self, $file, $field, $value_var, $pos_var) = @_;
  return $self->_get_decode_expression_for_type($file, $field->type, $value_var, $pos_var);
}

sub _get_decode_expression_for_type {
  my ($self, $file, $type, $value_var, $pos_var) = @_;

  if ($type->isa('Proto::PL::AST::ScalarType')) {
    my $type_name = $type->name;

    if ($type_name eq 'string') {
      if ($pos_var eq '0') {

        # Regular field: value is already extracted content
        return "(Proto::PL::Runtime::_decode_string(${value_var}), length(${value_var}))";
      }
      else {
        # Map field: need to decode length-delimited
        return
          "do { my (\$len, \$len_consumed) = Proto::PL::Runtime::_decode_varint(${value_var}, ${pos_var}); my \$bytes = substr(${value_var}, ${pos_var} + \$len_consumed, \$len); (Proto::PL::Runtime::_decode_string(\$bytes), \$len_consumed + \$len) }";
      }
    }
    elsif ($type_name eq 'bytes') {
      if ($pos_var eq '0') {

        # Regular field: value is already extracted content
        return "(${value_var}, length(${value_var}))";
      }
      else {
        # Map field: need to decode length-delimited
        return
          "do { my (\$len, \$len_consumed) = Proto::PL::Runtime::_decode_varint(${value_var}, ${pos_var}); my \$bytes = substr(${value_var}, ${pos_var} + \$len_consumed, \$len); (\$bytes, \$len_consumed + \$len) }";
      }
    }
    elsif ($type_name eq 'bool') {
      if ($pos_var eq '0') {

        # Regular field: value is already decoded
        return "${value_var}, 0";
      }
      else {
        # Map field: need to decode varint
        return "Proto::PL::Runtime::_decode_varint(${value_var}, ${pos_var})";
      }
    }
    elsif ($type_name =~ /^sint/) {
      my $zigzag_func = $type_name eq 'sint32' ? '_decode_zigzag32' : '_decode_zigzag64';
      if ($pos_var eq '0') {

        # Regular field: value is already decoded, just apply zigzag
        return "(Proto::PL::Runtime::${zigzag_func}(${value_var}), 0)";
      }
      else {
        # Map field: need to decode varint then apply zigzag
        return "do { my (\$v, \$c) = Proto::PL::Runtime::_decode_varint(${value_var}, ${pos_var}); (Proto::PL::Runtime::${zigzag_func}(\$v), \$c) }";
      }
    }
    elsif ($type_name =~ /^(int|uint)/) {
      if ($pos_var eq '0') {

        # Regular field: value is already decoded
        return "${value_var}, 0";
      }
      else {
        # Map field: need to decode varint
        return "Proto::PL::Runtime::_decode_varint(${value_var}, ${pos_var})";
      }
    }
    elsif ($type_name eq 'fixed32') {
      return "(Proto::PL::Runtime::_decode_fixed32(${value_var}), 4)";
    }
    elsif ($type_name eq 'fixed64') {
      return "(Proto::PL::Runtime::_decode_fixed64(${value_var}), 8)";
    }
    elsif ($type_name eq 'sfixed32') {
      return "(Proto::PL::Runtime::_decode_sfixed32(${value_var}), 4)";
    }
    elsif ($type_name eq 'sfixed64') {
      return "(Proto::PL::Runtime::_decode_sfixed64(${value_var}), 8)";
    }
    elsif ($type_name eq 'float') {
      return "(Proto::PL::Runtime::_decode_float(${value_var}), 4)";
    }
    elsif ($type_name eq 'double') {
      return "(Proto::PL::Runtime::_decode_double(${value_var}), 8)";
    }
  } ## end if ($type->isa('Proto::PL::AST::ScalarType'...))
  elsif ($type->isa('Proto::PL::AST::EnumType')) {
    if ($pos_var eq '0') {

      # Regular field: value is already decoded
      return "${value_var}, 0";
    }
    else {
      # Map field: need to decode varint
      return "Proto::PL::Runtime::_decode_varint(${value_var}, ${pos_var})";
    }
  }
  elsif ($type->isa('Proto::PL::AST::MessageType')) {

    # Handle case where message reference might not be set
    my $message = $type->message;
    if (not $message) {

      # Try to resolve the type by name using import-aware resolution
      my $type_name = $type->name;
      $message = $file->resolve_type($type_name);
      croak "Cannot find message type: $type_name" unless $message;
    }

    my $type_name = $message->perl_package_name($self->_get_package_prefix($file));
    return "(${type_name}->decode(${value_var}), length(${value_var}))";
  }

  croak "Unknown type for decoding: " . ref($type);
} ## end sub _get_decode_expression_for_type

sub _generate_hash_methods {
  my ($self, $message) = @_;

  my $code = <<'EOF';
sub _fields_to_hash {
    my ($self, $hash) = @_;
    
EOF

  for my $field (@{$message->fields}) {
    my $name = $field->name;

    if ($field->is_map) {
      $code .= <<EOF;
    \$hash->{${name}} = \$self->{${name}} if \$self->{${name}} && \%{\$self->{${name}}};
EOF
    }
    elsif ($field->is_repeated) {
      $code .= <<EOF;
    \$hash->{${name}} = \$self->{${name}} if \$self->{${name}} && \@{\$self->{${name}}};
EOF
    }
    elsif ($field->oneof) {

      # Oneof field - only include if this field is the active one
      my $oneof_name = $field->oneof;
      $code .= <<EOF;
    \$hash->{${name}} = \$self->{${name}} if \$self->{_oneof_${oneof_name}} eq '${name}' && defined \$self->{${name}};
EOF
    }
    else {
      my $presence_check = $field->is_optional ? "exists \$self->{_present}{${name}} && " : "";

      $code .= <<EOF;
    \$hash->{${name}} = \$self->{${name}} if ${presence_check}defined \$self->{${name}};
EOF
    }
  } ## end for my $field (@{$message...})

  $code .= <<'EOF';
}

EOF

  return $code;
} ## end sub _generate_hash_methods

sub _generate_nested_message_code {
  my ($self, $message, $parent_package, $file) = @_;

  my $package_name = "${parent_package}::" . $message->name;

  my $code = <<EOF;
package ${package_name};
our \@ISA = qw(Proto::PL::Runtime::Message);

EOF

  # Generate the same structure as top-level messages
  $code .= $self->_generate_constructor($message);

  for my $field (@{$message->fields}) {
    $code .= $self->_generate_field_accessor($field);
  }

  # Generate oneof accessors and methods for nested messages
  for my $oneof (@{$message->oneofs}) {
    $code .= $self->_generate_oneof_methods($oneof);
  }

  # Generate helper methods for nested messages
  $code .= $self->_generate_helper_methods($message);

  $code .= $self->_generate_encode_method($message, $file);
  $code .= $self->_generate_decode_method($message, $file);
  $code .= $self->_generate_hash_methods($message);

  # Recursively generate nested types
  for my $nested (@{$message->nested_messages}) {
    $code .= $self->_generate_nested_message_code($nested, $package_name, $file);
  }

  for my $nested (@{$message->nested_enums}) {
    $code .= $self->_generate_nested_enum_code($nested, $package_name);
  }

  return $code;
} ## end sub _generate_nested_message_code

sub _generate_enum_code {
  my ($self, $enum, $package_prefix) = @_;

  my $package_name = $enum->perl_package_name($package_prefix);

  my $code = <<EOF;
package ${package_name};

use strict;
use warnings;

# Enum values
use constant {
EOF

  for my $value (@{$enum->values}) {
    $code .= sprintf("    %s => %d,\n", $value->name, $value->number);
  }

  $code .= <<'EOF';
};

# Export all constants
our @EXPORT = qw(
EOF

  for my $value (@{$enum->values}) {
    $code .= "    " . $value->name . "\n";
  }

  $code .= <<'EOF';
);

sub import {
    my $caller = caller;
    no strict 'refs';
    for my $const (@EXPORT) {
        *{"${caller}::${const}"} = \&{$const};
    }
}

1;

EOF

  $code .= $self->_generate_enum_pod_documentation($enum, $package_name);

  return $code;
} ## end sub _generate_enum_code

sub _generate_nested_enum_code {
  my ($self, $enum, $parent_package) = @_;

  my $package_name = "${parent_package}::" . $enum->name;

  my $code = <<EOF;
package ${package_name};

use constant {
EOF

  for my $value (@{$enum->values}) {
    $code .= sprintf("    %s => %d,\n", $value->name, $value->number);
  }

  $code .= <<'EOF';
};

# Add encode method
sub encode {
    my ($value) = @_;
    require Proto::PL::Runtime;
    return Proto::PL::Runtime::_encode_varint($value);
}

# Add decode method  
sub decode {
    my ($bytes) = @_;
    require Proto::PL::Runtime;
    my ($value, $consumed) = Proto::PL::Runtime::_decode_varint($bytes);
    return $value;
}

EOF

  return $code;
} ## end sub _generate_nested_enum_code

sub _generate_pod_documentation {
  my ($self, $message, $package_name) = @_;

  my $code = <<EOF;
__END__

=head1 NAME

${package_name} - Protocol Buffers message class

=head1 SYNOPSIS

    use ${package_name};
    
    my \$msg = ${package_name}->new();
    
    # Set fields
EOF

  for my $field (@{$message->fields}) {
    $code .= "    \$msg->" . $field->name . "('" . $field->name . " value');\n";
  }

  $code .= <<'EOF';
    
    # Encode to bytes
    my $bytes = $msg->encode();
    
    # Decode from bytes
    my $decoded = ${package_name}->decode($bytes);

=head1 DESCRIPTION

This class represents a Protocol Buffers message.

=head1 FIELDS

EOF

  for my $field (@{$message->fields}) {
    my $type_desc = ref($field->type) =~ /::(\w+)Type$/ ? $1 : 'unknown';
    my $label     = $field->label || 'singular';
    if ($field->oneof) {
      $code .= sprintf("=head2 %s (%s %s, oneof: %s)\n\n", $field->name, $label, lc($type_desc), $field->oneof);
    }
    else {
      $code .= sprintf("=head2 %s (%s %s)\n\n", $field->name, $label, lc($type_desc));
    }
  }

  # Document oneofs
  if (@{$message->oneofs}) {
    $code .= <<'EOF';

=head1 ONEOFS

EOF
    for my $oneof (@{$message->oneofs}) {
      my $oneof_name = $oneof->name;
      $code .= "=head2 ${oneof_name}\n\n";
      $code .= "Fields: " . join(', ', map { $_->name } @{$oneof->fields}) . "\n\n";
      $code .= "Methods: which_${oneof_name}(), clear_${oneof_name}()";
      for my $field (@{$oneof->fields}) {
        $code .= ", has_" . $field->name . "()";
      }
      $code .= "\n\n";
    }
  }

  $code .= <<'EOF';

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

EOF

  # Document oneof methods
  if (@{$message->oneofs}) {
    for my $oneof (@{$message->oneofs}) {
      my $oneof_name = $oneof->name;
      $code .= <<'EOF';

=head2 which_${oneof_name}()

Returns the name of the currently set field in the ${oneof_name} oneof, or undef if none is set.

=head2 clear_${oneof_name}()

Clears all fields in the ${oneof_name} oneof.

EOF
      for my $field ($oneof->fields->@*) {
        my $field_name = $field->name;
        $code .= <<'EOF';

=head2 has_${field_name}()

Returns true if ${field_name} is the currently set field in the ${oneof_name} oneof.

EOF
      }
    } ## end for my $oneof (@{$message...})
  } ## end if (@{$message->oneofs...})

  $code .= <<'EOF';
=head1 AUTHOR

Generated by pl_protoc

=cut
EOF

  return $code;
} ## end sub _generate_pod_documentation

sub _generate_enum_pod_documentation {
  my ($self, $enum, $package_name) = @_;

  my $code = <<EOF;
__END__

=head1 NAME

${package_name} - Protocol Buffers enum

=head1 SYNOPSIS

    use ${package_name};
    
    my \$value = RED;  # Imported constant

=head1 DESCRIPTION

This module defines constants for a Protocol Buffers enum.

=head1 VALUES

EOF

  for my $value (@{$enum->values}) {
    $code .= sprintf("=head2 %s = %d\n\n", $value->name, $value->number);
  }

  $code .= <<'EOF';

=head1 AUTHOR

Generated by pl_protoc

=cut
EOF

  return $code;
} ## end sub _generate_enum_pod_documentation

sub _resolve_field_type {
  my ($self, $field, $file) = @_;

  # If it's already properly typed, return as-is
  return $field->type unless $field->type->isa('Proto::PL::AST::MessageType');

  my $type_name = $field->type->name;

  # Use import-aware resolution
  my $resolved_type = $file->resolve_type($type_name);

  if ($resolved_type) {
    if ($resolved_type->isa('Proto::PL::AST::Enum')) {
      return Proto::PL::AST::EnumType->new(
        name => $type_name,
        enum => $resolved_type
      );
    }
    elsif ($resolved_type->isa('Proto::PL::AST::Message')) {
      my $msg_type = $field->type;
      $msg_type->{message} = $resolved_type unless $msg_type->{message};
      return $msg_type;
    }
  }

  # If not found, return as-is (will cause error as before)
  return $field->type;
} ## end sub _resolve_field_type

1;

__END__

=head1 NAME

Proto::PL::Generator - Code generator for Protocol Buffers

=head1 SYNOPSIS

    use Proto::PL::Generator;
    
    my $generator = Proto::PL::Generator->new(
        output_dir => 'lib',
    );
    
    $generator->add_file($parsed_file);
    $generator->generate_all();

=head1 DESCRIPTION

This module generates Perl code from Protocol Buffers AST.

=head1 AUTHOR

Generated by pl_protoc

=cut
