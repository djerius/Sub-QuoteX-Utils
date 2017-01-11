#! perl

use strict;
use warnings;

use Test2::Bundle::Extended;

use Sub::QuoteX::Utils ':all';

# check that result storage works

{
    package Class;
    sub new { bless {}, shift }
    sub method { 33, 44 }
}

my $coderef = sub { 33, 44 };
my $string = '( 33, 44 );';

# non-lexical so generated code can see it
our $expected = [ 33, 44 ];

sub cmp_inlinify_store {

    my $gc  = shift;
    my $ctx = context();

    my $got = quote_subs(
        @_,
        \'return \@x',
        {
            lexicals => '@x',
            capture  => $gc
        } )->();

    my $ok = is( $got, $expected, "array" );

    $ctx->release;

    return $ok;
}

subtest 'coderef' => sub {

    my %gc;
    my $code = inlinify_coderef( \%gc, $coderef, store => '@x' );
    cmp_inlinify_store( \%gc, $code );
};

subtest 'method' => sub {

    my %gc;
    my $object = Class->new;
    my $code = inlinify_method( \%gc, $object, 'method', store => '@x' );
    cmp_inlinify_store( \%gc, $code );
};

subtest 'code' => sub {

    my %gc;
    my $code = inlinify_code( \%gc, $string, store => '@x' );
    cmp_inlinify_store( \%gc, $code );
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
