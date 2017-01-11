#! perl

use strict;
use warnings;

use Test2::Bundle::Extended;

use Sub::QuoteX::Utils ':all';

# check that result storage works

{
    package Class;
    sub new { bless {}, shift }
    # force list return
    sub method { @{[ 33, 44 ]} }
}

my $coderef = sub { @{[ 33, 44 ]} };
my $string = ' @{[ 33, 44 ]};';

# non-lexical so generated code can see it
our $expected = [ 33, 44 ];

sub cmp_inlinify_store {

    my $sub = shift;

    my $ctx = context();

    my $ok = 1;

    {
	my %gc;

	my @got = quote_subs(
			     $sub->( \%gc, @_, store => '@x' ),
			     \'return @x',
			     {
			      lexicals => '@x',
			      capture => \%gc,
			     } )->();

	$ok &= is( \@got, $expected, 'array');

    }


    {
	my %gc;

	my $got = quote_subs(
			     $sub->( \%gc, @_, store => '$x' ),
			     \'return $x',
			     {
			      lexicals => '$x',
			      capture => \%gc,
			     } )->();
	$ok &= is( $got, scalar @$expected, 'scalar' );

    }


    $ctx->release;

    return $ok;
}

subtest 'coderef' => sub {

    cmp_inlinify_store( \&inlinify_coderef, $coderef );

};

subtest 'method' => sub {

    my $object = Class->new;
    cmp_inlinify_store( \&inlinify_method, $object, 'method' );
};

subtest 'code' => sub {

    cmp_inlinify_store( \&inlinify_code, $string );
};


subtest 'quote_subs' => sub {

    my $object = Class->new;
    quote_subs(
        \q[use vars '$expected';],
        [ $coderef, store => '@coderef' ],
        [ $object, 'method', store => '@method' ],
        [ $string, store => '@code' ],
        \qq[is( \$expected, [@{[ join ',', @$expected ]}], 'fiducial' );],
        \q[is( \@coderef, $expected, 'coderef' );],
        \q[is( \@method, $expected, 'method' );],
        \q[is( \@code, $expected, 'code' );],
    )->();
};

done_testing;
