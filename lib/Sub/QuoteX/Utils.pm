package Sub::QuoteX::Utils;

# ABSTRACT: Sugar for Sub::Quote

use strict;
use warnings;

our $VERSION = '0.04';

use Sub::Quote
  qw( quoted_from_sub inlinify capture_unroll sanitize_identifier quote_sub );

use Scalar::Util qw( weaken refaddr blessed );
use Carp;

use Exporter 'import';

our @EXPORT_OK = qw(
  quote_subs
  inlinify_coderef
  inlinify_method
  inlinify_code
);

our %EXPORT_TAGS = ( all => \@EXPORT_OK );


=func quote_subs

  my $coderef = quote_subs( $spec, ?$spec, ... , ?\%options );

Creates a compiled subroutine from syntactically complete chunks of
code or from snippets of code.

Chunks may be extracted from code previously inlined by L<Sub::Quote>,
specified as strings containing code, or generated to accomodate
invoking object methods or calling non-inlineable code.

By default each chunk will localize C<@_> to avoid changing C<@_> for
the other chunks. This can be changed on a per-chunk basis by
specifying the C<local> option in each specification.

Specifications may take one of the following forms:

=over

=item C<$coderef>

If C<$coderef> is inlineable (i.e, generated by
L<Sub::Quote/quote_sub>) it will be directly inlined, else code to
invoke it will be generated.

=item C<[ $coderef, %option ]>

This is another way of specifying a code reference, allowing
more manipulation; see L</inlinify_coderef> for available options.

=item C<[ $object, $method, %option ]>

Inline a method call. A weakened reference to C<$object> is kept to
avoid leaks. Method lookup is performed at runtime.  See
L</inlinify_method> for available options.

=item C<[ $string, %option ]>

Inline a chunk of code in a string. See L</inlinify_code> for
available options.

=item C<$scalarref>

Inline a snippet of code stored in the referenced scalar.  Snippets
need not be syntactically complete, and thus may be used to enclose
chunks in blocks. For example, to catch exceptions thrown by a chunk:

   $coderef = quote_subs( \'eval {', \&chunk_as_func, \'};' );

Specify any required captured values in the C<capture> option to
C<quote_subs>.

=back

Options which may be passed as the last parameter include all of the
options accepted by L<< C<Sub::Quote::quote_sub>|Sub::Quote/quote_sub
>>, as well as:

=over

=item C<name> => I<string>

An optional name for the compiled subroutine.

=item C<capture> => I<hashref>

A hash containing captured variable names and values.  See the
documentation of the C<\%captures> argument to L<Sub::Quote/quote_sub>
for more information.



=back


=cut

# quote_subs( [], [], {} );
sub quote_subs {

    my @caller = caller( 0 );

    # need to duplicate these bits from Sub::Quote::quote_sub, as they rely upon caller
    my %option = (
        package      => $caller[0],
        hints        => $caller[8],
        warning_bits => $caller[9],
        hintshash    => $caller[10],
        'HASH' eq ref $_[-1] ? %{ pop @_ } : (),
    );
    my %qsub_opts
      = map { $_ => $option{$_} } qw[ package hints warning_bits hintshash ];

    if ( $option{name} ) {
        my $subname = $option{name};
        my $package = $subname =~ s/(.*)::// ? $1 : $option{package};
        $option{name} = join '::', $package, $subname;
    }

    my %global_capture = %{ delete $option{capture} || {} };

    my @code;
    for my $thing ( @_ ) {

        my $arr = 'ARRAY' eq ref $thing ? $thing : [$thing];

        if ( 'CODE' eq ref $arr->[0] ) {

            push @code, inlinify_coderef( \%global_capture, @$arr ), q[;] ;
        }

        elsif ( blessed $arr->[0] ) {

            push @code, inlinify_method( \%global_capture, @$arr ), q[;] ;
        }

        elsif ( !ref $arr->[0] ) {

            push @code, inlinify_code( \%global_capture, @$arr ), q[;] ;
        }

	elsif ( 'SCALAR' eq ref $arr->[0] ) {

	    push @code, ${ $arr->[0] };

	}
	else {

	    croak( "don't understand argument in $_[@{[ scalar @code ]}]\n" );
	}
    }

    quote_sub(
        ( delete $option{name} || () ),
        join( "\n", @code ),
        \%global_capture, \%qsub_opts
    );

}

sub _process_options {

    my ( $option, $capture ) = @_;

    $option->{provide_args} = 1;

    if ( exists $option->{args} ) {

	if ( defined $option->{args} ) {

	    if ( my $ref = ref $option->{args} ) {

		my $arg = $option->{args};
		$capture->{'$arg'} = \$arg;

		$option->{args}
		  = 'ARRAY' eq $ref ? '@{$arg}'
		    : 'HASH' eq $ref  ? '%{$arg}'
		      :   croak( q[args option must be an arrayref, hashref, or string] );
	    }
	}

	# args explicitly undef, set @_ to ();
	else {

            $option->{args} = '()';
	    $option->{provide_args} = 0;
	}
    }

    else {

	$option->{args} = '@_';
    }
}


=func inlinify_coderef

  my $code = inlinify_coderef( \%global_capture, $coderef, %options );

Generate code which will execute C<$coderef>. If C<$coderef> is
inlineable, it is inlined, else code which will invoke it is generated.

See L</Captures> for more information on C<%global_capture>.

Available options are:

=over

=item C<name> => I<string>

An optional string used as part of the hash key for this chunk's captures.

=item C<local> => I<boolean>

If true (the default) changes to C<@_> will be local, e.g.

  local @_ = ...;

rather than

  @_ = ...;

=item C<args> => I<arrayref> | I<hashref> | I<string> | C<undef>

This specified the values of C<@_>.

=over

=item *

if not specified, the value of C<@_> is unchanged.

=item *

if the value is C<undef>, C<@_> will be empty.

=item *

if the value is a reference to an array or hash, C<@_> will be set
equal to its contents. Note that the reference is I<cached>, so

=over

=item *

changes to its contents will be reflected in calls to the code.

=item *

there is the danger of memory leaks, as any non-weakened references in
the structure will be destroyed only when both C<%global_capture> and
any subroutines based on this are destroyed.

=back

=item *

if a string, this is inlined directly, e.g.

  args => q[( 'FRANK' )]

results in

  @_ = ( 'FRANK' )

=back

=back

=cut

sub inlinify_coderef {

    my ( $global_capture, $coderef, %option ) = @_;

    croak( "\$coderef must be a CODEREF\n" )
      unless 'CODE' eq ref $coderef;

    my $qtd = quoted_from_sub( $coderef );

    my %capture;
    _process_options( \%option, \%capture );

    my $code;

    if ( $qtd ) {

	$code = $qtd->[1];
	$capture{$_} = $qtd->[2]{$_} for keys %{ $qtd->[2] };
    }
    else {

	$code = q[&$sub;];
	$capture{ '$sub' } = \$coderef;
    }


    inlinify_code( $global_capture, $code, capture => \%capture, %option );
}

=func inlinify_method

  my $code = inlinify_method( \%global_capture, $object, $method,  %options );

Generate code which will invoke the method named by C<$method> on
C<$object>.  While method resolution is performed at runtime,
C<inlinify_method> checks that C<$method> is available for C<$object>
and will C<croak> if not.

See L</Captures> for more information on C<%global_capture>.

Available options are:

=over

=item C<name> => I<string>

An optional string used as part of the hash key for this chunk's captures.

=item C<local> => I<boolean>

If true (the default) changes to C<@_> will be local, e.g.

  local @_ = ...;

rather than

  @_ = ...;

=item C<args> => I<arrayref> | I<hashref> | I<string> | C<undef>

This specified the values of C<@_>.

=over

=item *

if not specified, the value of C<@_> is unchanged.

=item *

if the value is C<undef>, C<@_> will be empty.

=item *

if the value is a reference to an array or hash, C<@_> will be set
equal to its contents. Note that the reference is I<cached>, so

=over

=item *

changes to its contents will be reflected in calls to the code.

=item *

there is the danger of memory leaks, as any non-weakened references in
the structure will be destroyed only when both C<%global_capture> and
any subroutines based on this are destroyed.

=back

=item *

if a string, this is inlined directly, e.g.

  args => q[( 'FRANK' )]

results in

  @_ = ( 'FRANK' )

=back

=back

=cut

sub inlinify_method {

    my ( $global_capture, $object, $method, %option ) = @_;

    weaken $object;

    croak( "\$method must be a method name\n" )
      unless ref $method eq '';

    croak( "object does not provide a method named $method" )
      unless $object->can( $method );


    my %capture = ( '$r_object' => \\$object );

    $option{name} ||= refaddr $capture{'$r_object'};

    _process_options( \%option, \%capture );

    inlinify_code( $global_capture,
		   join( '',
			 '${$r_object}->',
			 $method,
			 $option{provide_args} ? '( @_ )' : '()',
			 'if ${$r_object};',
		       ),

		   capture => \%capture, %option );

}

=func inlinify_code

  my $code = inlinify_code( \%global_capture, $code,  %options );

Generate code which inlines C<$code> handling captures specified in C<%options>.

Available options are:

=over

=item C<capture> => I<hashref>

A hash containing captured variable names and values.  See the
documentation of the C<\%captures> argument to L<Sub::Quote/quote_sub>
for more information.

=item C<name> => I<string>

An optional string used as part of the hash key for this chunk's captures.

=item C<local> => I<boolean>

If true (the default) changes to C<@_> will be local, e.g.

  local @_ = ...;

rather than

  @_ = ...;

=item C<args> => I<arrayref> | I<hashref> | I<string> | C<undef>

This specified the values of C<@_>.

=over

=item *

if not specified, the value of C<@_> is unchanged.

=item *

if the value is C<undef>, C<@_> will be empty.

=item *

if the value is a reference to an array or hash, C<@_> will be set
equal to its contents. Note that the reference is I<cached>, so

=over

=item *

changes to its contents will be reflected in calls to the code.

=item *

there is the danger of memory leaks, as any non-weakened references in
the structure will be destroyed only when both C<%global_capture> and
any subroutines based on this are destroyed.

=back

=item *

if a string, this is inlined directly, e.g.

  args => q[( 'FRANK' )]

results in

  @_ = ( 'FRANK' )

=back

=back

=cut

sub inlinify_code {

    my ( $global_capture, $code, %option ) = @_;

    my %capture = %{ delete $option{capture} || {} };

    _process_options( \%option, \%capture );

    my $r_capture = \%capture;

    $option{name} ||= refaddr $r_capture;
    my $cap_name = q<$capture_for_> . sanitize_identifier( $option{name} );
    $global_capture->{$cap_name} = \$r_capture;

    $option{args} ||= '@_';
    $option{local} = 1 unless defined $option{local};


    inlinify( $code, $option{args}, capture_unroll( $cap_name, $r_capture, 0 ),
        $option{local} );
}

1;

# COPYRIGHT

__END__


=head1 SYNOPSIS

# EXAMPLE: examples/synopsis.pl

=head1 DESCRIPTION

B<Sub::QuoteX::Utils> provides a simplified interface to the process of
combining L<Sub::Quote> compatible code references with new code.

L<Sub::Quote> provides a number of routines to make code more
performant by inlining syntactically complete chunks of code into a
single compiled subroutine.

When a chunk of code is compiled into a subroutine by L<<
C<Sub::Quote::quote_sub()>|Sub::Quote/quote_sub >>, B<Sub::Quote>
keeps track of the code and any captured variables used to construct
that subroutine, so that new code can be added to the original code
and the results compiled into a new subroutine.

B<Sub::QuoteX::Utils> makes that latter process a little easier.

=head2 Captures

B<Sub::Quote> keeps track of captured variables in hashes, I<copying>
the values.  For example,

# EXAMPLE: examples/captures.pl

When combining chunks of inlined code, each chunk has it's own set of
captured values which must be kept distinct.

L</quote_subs> manages this for the caller, but when using the low
level routines ( L</inlinify_coderef>, L</inlinify_method>,
L</inlinify_code> ) the caller must manage the captures.  These
routines store per-chunk captures in their C<\%global_capture> argument.
The calling routine optionally may provide a mnemonic (but unique!)
string which will be part of the key for the chunk.

The C<%global_capture> hash should be passed to
L<Sub::Quote/quote_sub>, when the final subroutine is compiled.  For
example,

  my %global_capture;
  my $code = inlinify_coderef( \%global_capture, $coderef, %options );

  # add more code to $code [...]

  $new_coderef = Sub::Quote::quote_sub( $code, \%global_capture );




=head1 SEE ALSO

L<Sub::Quote>
