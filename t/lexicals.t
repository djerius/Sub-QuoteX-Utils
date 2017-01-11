#! perl

use strict;
use warnings;

use Test2::Bundle::Extended;

use Sub::QuoteX::Utils qw[ quote_subs ];


# basic test that tests will work

subtest 'tests' => sub {

    # test that using lexicals that are not declared causes an error

    ok( lives { quote_subs( \'my $xxxx = 33' )->() },
        "declaration"
    );

    like(
        dies { quote_subs( \'$xxxx = 33' )->() },
        qr/forget to declare/,
        "no declaration"
    ) or bail_out( "can't detect if declaration is required\n" );

};

subtest 'lexicals' => sub {

    ok( lives {
	quote_subs( \'$xxxx = 33', { lexicals => '$xxxx' }  )->() },
        "scalar"
    );

    ok( lives {
	quote_subs( \'$xxxx = 33;', \'$yyyy = 44;',
		    { lexicals => [ '$xxxx', '$yyyy' ] }  )->() },
        "array"
    );

};

done_testing;
