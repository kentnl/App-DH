use strict;
use warnings;

package App::DH;
BEGIN {
  $App::DH::AUTHORITY = 'cpan:KENTNL';
}
{
  $App::DH::VERSION = '0.001';
}

# ABSTRACT: Deploy your DBIx::Class Schema to DDL/Database via DBIx::Class::DeploymentHandler

use DBIx::Class::DeploymentHandler;
use Moose;
use MooseX::AttributeShortcuts;


with 'MooseX::Getopt';


has connection_name => (
  traits        => ['Getopt'],
  is            => ro =>,
  isa           => Str =>,
  required      => 1,
  cmd_aliases   => c =>,
  default       => sub { 'development' },
  documentation => 'either a valid DBI DSN or an alias configured by DBIx::Class::Schema::Config',
);


has force => (
  traits        => ['Getopt'],
  is            => ro =>,
  isa           => Bool =>,
  default       => sub { 0 },
  cmd_aliases   => f =>,
  documentation => 'forcefully replace existing DDLs. [DANGER]',
);


has schema => (
  traits        => ['Getopt'],
  is            => ro =>,
  isa           => Str =>,
  required      => 1,
  cmd_aliases   => s =>,
  documentation => 'the class name of the schema to generate DDLs/deploy for',
);


has include => (
  traits        => ['Getopt'],
  is            => ro =>,
  isa           => ArrayRef =>,
  default       => sub { [] },
  cmd_aliases   => I =>,
  documentation => 'paths to load into @INC',
);


has script_dir => (
  traits        => ['Getopt'],
  is            => ro =>,
  isa           => Str =>,
  default       => sub { 'share/ddl' },
  cmd_aliases   => o =>,
  documentation => 'output path',
);


has database => (
  traits        => ['Getopt'],
  is            => ro =>,
  isa           => ArrayRef =>,
  default       => sub { [qw( PostgreSQL SQLite )] },
  cmd_aliases   => d =>,
  documentation => 'database backends to generate DDLs for. See SQL::Translator::Producer::* for valid values',
);

has _dh     => ( is => 'lazy' );
has _schema => ( is => 'lazy' );

sub _build__schema {
  my ($self) = @_;
  require lib;
  lib->import($_) for @{ $self->include };
  require Module::Runtime;
  my $class = Module::Runtime::use_module( $self->schema );
  return $class->connect( $self->connection_name );
}

sub _build__dh {
  my ($self) = @_;
  DBIx::Class::DeploymentHandler->new(
    {
      schema           => $self->_schema,
      force_overwrite  => $self->force,
      script_directory => $self->script_dir,
      databases        => $self->database,
    }
  );
}


sub cmd_write_ddl {
  my ($self) = @_;
  $self->_dh->prepare_install;
  my $v = $self->_dh->schema_version;
  if ( $v > 1 ) {
    $self->_dh->prepare_upgrade(
      {
        from_version => $v - 1,
        to_version   => $v
      }
    );
  }
}


sub cmd_install {
  my $self = shift;
  $self->_dh->install;
}


sub cmd_upgrade { shift->_dh->upgrade }

my (%cmds) = (
  write_ddl => \&cmd_write_ddl,
  install   => \&cmd_install,
  upgrade   => \&cmd_upgrade,
);
my (%cmd_desc) = (
  write_ddl => 'only write ddl files',
  install   => 'install to the specified database connection',
  upgrade   => 'upgrade the specified database connection',
);
my $list_cmds = join q[ ], sort keys %cmds;
my $list_cmds_opt = '(' . ( join q{|}, sort keys %cmds ) . ')';
my $list_cmds_usage =
  ( join qq{\n}, q{}, qq{\tcommands:}, q{}, ( map { ( sprintf qq{\t%-30s%s}, $_, $cmd_desc{$_} ) } sort keys %cmds ), q{} );

around print_usage_text => sub {
  my ( $orig, $self, $usage ) = @_;
  my ($text) = $usage->text();
  $text =~ s{
        ( long\s+options[.]+[]] )
    } {
        $1 . ' ' . $list_cmds_opt
    }msex;
  *STDERR->flush();
  print "\n";
  print $text;
  print $list_cmds_usage;
  print "\n";
  exit 0;
};

sub run {
  my ($self) = @_;
  my ( $cmd, @what ) = @{ $self->extra_argv };
  die "Must supply a command\nCommands: $list_cmds\n" unless $cmd;
  die "Extra argv detected - command only please\n" if @what;
  die "No such command ${cmd}\nCommands: $list_cmds\n"
    unless exists $cmds{$cmd};
  my $code = $cmds{$cmd};
  $self->$code();
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

=encoding utf-8

=head1 NAME

App::DH - Deploy your DBIx::Class Schema to DDL/Database via DBIx::Class::DeploymentHandler

=head1 VERSION

version 0.001

=head1 SYNOPSIS

Basic usage:

    #!/usr/bin/env perl
    #
    # dh.pl

    use App::DH;
    App::DH->new_with_options->run;

=head1 COMMANDS

=head2 write_ddl

Only generate ddls for deploy/upgrade

    DBICDH [...params] write_ddl

=head2 write_ddl

Install to connection L</--connection_name>

    DBICDH [...params] install

=head2 upgrade

Upgrade connection L</--connection_name>

    DBICDH [...params] upgrade

=head1 PARAMETERS

=head2 --connection_name

    -c/--connection_name

Specify the connection details to use for deployment.
Can be a name of a configuration in a C<DBIx::Class::Schema::Config> configuration if the L</--schema> uses it.

    --connection_name 'dbi:SQLite:/path/to/db'

    -cdevelopment

=head2 --force

Overwrite existing DDL files of the same version.

    -f/--force

=head2 --schema

    -s/--schema

The class name of the schema to load for DDL/Deployment

    -sMyProject::Schema
    --schema MyProject::Schema

=head2 --include

    -I/--include

Add a given library path to @INC prior to loading C<schema>

    -I../lib
    --include ../lib

May be specified multiple times.

=head2 --script_dir

    -o/--script_dir

Specify where to write the per-backend DDL's.

Default is ./share/ddl

    -o/tmp/ddl
    --script_dir /tmp/ddl

=head2 --database

    -d/--database

Specify the C<SQL::Translator::Producer::*> backend to use for generating DDLs.

    -dSQLite
    --database PostgreSQL

Can be specified multiple times. 

Default is C<[ PostgreSQL SQLite ]>

=head1 AUTHOR

Kent Fredric <kentfredric@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Kent Fredric <kentfredric@gmail.com>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut