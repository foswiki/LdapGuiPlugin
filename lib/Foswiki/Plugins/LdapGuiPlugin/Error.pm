package Foswiki::Plugins::LdapGuiPlugin::Error;

use strict;
use warnings;

sub new {
    my $class = shift;
    my $this  = {
        errors     => [],
        errorCount => 0,
    };
    bless $this, $class;
    return $this;
}

=pod

addError ( $error, \@message ) -> $boolean

Adds the error and the list of messages to the list of errors collected in the object.

Returns true on success.

=cut

sub addError {
    my $this  = shift;
    my $error = shift;
    my $msg   = shift;
    return 0 unless ( $error && $msg );
    push @{ $this->{errors} }, { error => $error, msg => $msg };
    $this->{errorCount}++;
    return 1;
}

=pod

hasError ( ) -> $boolean

Returns true if the object contains at least on error.

=cut

sub hasError {
    my $this = shift;
    return ( $this->{errorCount} > 0 ) || ( scalar @{ $this->{errors} } > 0 );
}

=pod
$writeErrorsToDebug ( ) -> 1

Writes all errors and messages to the debug.log file.

=cut

sub writeErrorsToDebug {
    my $this  = shift;
    my $count = 0;
    if ( $this->{errorCount} ) {
        Foswiki::Func::writeDebug( "ERROR COUNT:" . $this->{errorCount} );
        foreach my $err ( @{ $this->{errors} } ) {
            Foswiki::Func::writeDebug( "ERROR $count: " . $err->{error} );
            Foswiki::Func::writeDebug("MSG: $_") foreach ( @{ $err->{msg} } );
            $count++;
        }
    }
    else {
        Foswiki::Func::writeDebug("NO ERRORS");
    }
    return 1;
}

sub getErrorString {
    return 0;
}

sub errorRenderHTML {
    my $this  = shift;
    my $web   = shift;
    my $topic = shift;
    my $count = 0;
    my $linkback =
        $Foswiki::{cfg}{DefaultUrlHost}
      . $Foswiki::{cfg}{ScriptUrlPaths}{view}
      . "/$topic";
    my $linebreak = '<br/>';
    my $insert =
'<h2>There was an error while processing your request. Please contact your administrator and give him the information listed below:</h2><br/>';
    $insert = $insert
      . "<h3>Total number of errors: $this->{errorCount}</h3>$linebreak Error history:$linebreak $linebreak";

    foreach my $error ( @{ $this->{errors} } ) {
        $insert =
            $insert
          . "Error number: $count $linebreak Error code: "
          . $error->{error}
          . $linebreak
          . "Message:$linebreak";
        foreach my $msg ( @{ $error->{msg} } ) {
            $insert = $insert . "$msg $linebreak";
        }
        $count++;
    }
    $insert =
      $insert . $linebreak . $linebreak . "<a href=\"$linkback\">Go back</a>";
    use CGI;
    my $page =
        CGI::start_html( -title => 'LDAP error page' )
      . $insert
      . CGI::end_html();
    return $page;
}

1;
