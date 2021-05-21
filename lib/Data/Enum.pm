package Data::Enum;

# ABSTRACT: fast, immutable enumeration classes

use v5.10;

use strict;
use warnings;

use Package::Stash;
use List::Util 1.45 qw/ uniqstr /;
use Scalar::Util qw/ blessed refaddr /;

# RECOMMEND PREREQ: Package::Stash::XS

use overload ();

our $VERSION = 'v0.2.3';

=head1 SYNOPSIS

  use Data::Enum;

  my $color = Data::Enum->new( qw[ red yellow blue green ] );

  my $red = $color->new("red");

  $red->is_red;    # "1"
  $red->is_yellow; # "" (false)
  $red->is_blue;   # "" (false)
  $red->is_green;  # "" (false)

  say $red;        # outputs "red"

  $red eq $color->new("red"); # true

  $red eq "red"; # true

=head1 DESCRIPTION

This module will create enumerated constant classes with the following
properties:

=over

=item *

Any two classes with the same elements are equivalent.

The following two classes are the I<same>:

  my $one = Data::Enum->new( qw[ foo bar baz ] );
  my $two = Data::Enum->new( qw[ foo bar baz ] );

=item *

All class instances are singletons.

  my $one = Data::Enum->new( qw[ foo bar baz ] );

  my $a = $one->new("foo")
  my $b = $one->new("foo");

  refaddr($a) == refaddr($b); # they are the same thing

=item *

Methods for checking values are fast.

  $a->is_foo; # constant time

  $a eq $b;   # compares refaddr

=item *

Values are immutable (read-only).

=back

This is done by creating a unique internal class name based on the
possible values.  Each value is actually a subclass of that class,
with the appropriate C<is_> method returning a constant.

=method new

  my $class = Data::Enum->new( @values );

This creates a new anonymous class. Values can be instantiated with a
constructor:

  my $instance = $class->new( $value );

Calling the constructor with an invalid value will throw an exception.

Each instance will have an C<is_> method for each value.

Each instance stringifies to its value.

=method values

  my @values = $class->values;

Returns a list of valid values, stringified and sorted with duplicates
removed.

This was added in v0.2.0.

=method predicates

  my @predicates = $class->predicates;

Returns a list of predicate methods for each value.

A hash of predicates to values is roughly

  use List::Util 1.56 'mesh';

  my %handlers = mesh [ $class->values ], [ $class->predicates ];

This was added in v0.2.1.

=cut

my %Cache;
my $Counter;

sub new {
    my $this = shift;

    my @values = uniqstr( sort map { "$_" } @_ );

    die "has no values" unless @values;

    die "values must be alphanumeric" if !!grep { /\W/ } @values;

    my $key = join chr(28), @values;

    if ( my $name = $Cache{$key} ) {
        return $name;
    }

    my $name = "Data::Enum::" . $Counter++;

    my $base = Package::Stash->new($name);

    my $_make_symbol = sub {
        my ($value) = @_;
        my $self = bless \$value, "${name}::${value}";
        Internals::SvREADONLY($value, 1);
        return $self;
    };

    my $_make_predicate = sub {
        my ($value) = @_;
        return "is_" . $value;
    };

    $base->add_symbol(
        '&new',
        sub {
            my ( $class, $value ) = @_;
            state $symbols = {
                map {
                    $_ => $_make_symbol->($_)
                } @values
            };
            exists $symbols->{"$value"} or die "invalid value: '$value'";
            return $symbols->{"$value"};
        }
    );

    $base->add_symbol( '&values', sub { return @values });

    $base->add_symbol( '&predicates', sub { return map { $_make_predicate->($_) } @values } );

    $name->overload::OVERLOAD(
        q{""} => sub { my ($self) = @_; return $$self; },
        q{eq} => sub {
            my ( $self, $arg ) = @_;
            return blessed($arg)
              ? refaddr($arg) == refaddr($self)
              : $arg eq $$self;
        },
        q{ne} => sub {
            my ( $self, $arg ) = @_;
            return blessed($arg)
              ? refaddr($arg) != refaddr($self)
              : $arg ne $$self;
        },
    );

    for my $value (@values) {
        my $predicate = $_make_predicate->($value);
        $base->add_symbol( '&' . $predicate, sub { '' } );
        my $elem    = "${name}::${value}";
        my $subtype = Package::Stash->new($elem);
        $subtype->add_symbol( '@ISA',  [$name] );
        $subtype->add_symbol( '&' . $predicate, sub { 1 } );
    }

    return $Cache{$key} = $name;
}

=head1 SEE ALSO

L<Class::Enum>

L<Object::Enum>

L<MooX::Enumeration>

L<MooseX::Enumeration>

L<Type::Tiny::Enum>

=cut

1;
