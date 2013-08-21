package Foswiki::Plugins::LdapGuiPlugin::Renderer;

use strict;
use warnings;

use URI::Escape;
use CGI ':standard';

=pod
things to render:

entries
entry diffs
error messages


=cut

sub new {
    my $class = shift;
    my $this  = {
        css    => '',
        title  => '',
        insert => ''
    };
    bless $this, $class;
    return $this;
}

sub writePage {
    my $this = shift;
    my $page =
        CGI::start_html( -title => $this->{title} )
      . $this->{insert}
      . CGI::end_html();
    return $page;
}

sub css {
    my $this = shift;
    $this->{css} = shift;
}

sub entry {
    my $this   = shift;
    my $entry  = shift;
    my $insert = '';
    $insert = $insert . 'dn: ' . uri_unescape( $entry->dn ) . '<br/>';
    foreach my $attribute ( $entry->attributes ) {
        my $values = $entry->get_value( $attribute, asref => 1 );
        $attribute = uri_unescape($attribute);
        if ( defined $values ) {
            foreach my $value (@$values) {
                $value  = uri_unescape($value);
                $insert = $insert . "$attribute: $value<br/>";
            }
        }
        else {
            $insert = $insert . "$attribute: <br/>";
        }
    }
    $this->{insert} = $this->{insert} . $insert;
}

sub error {
    my $this    = shift;
    my $error   = shift;
    my $content = [ th( [ 'Error number', 'Error', 'Error messages' ] ) ];
    my $count   = 0;
    foreach my $error ( @{ $error->{errors} } ) {
        my $msgs = '';
        foreach my $msg ( @{ $error->{msg} } ) {
            $msgs = $msgs . "$msg<br/>";
        }
        push @$content,
          td(
            { -style => 'vertical-align:top' },
            [ $count, $error->{error}, $msgs ]
          );
        $count++;

    }
    $this->{insert} = $this->{insert}
      . table(
        {
            -border => 1,
            -style =>
'vertical-align:top; margin-right:10px; margin-bottom:6px border-collapse: collapse;',
            -cellspacing => "0",
            -cellpadding => "10"
        },
        caption('Error table:'),
        Tr( { -align => 'CENTER', -valign => 'TOP' }, $content )
      );

}

sub headl2 {
    my $this = shift;
    $this->{insert} = $this->{insert} . h2(shift);
}

sub headl3 {
    my $this = shift;
    $this->{insert} = $this->{insert} . h3(shift);
}

sub break {
    my $this  = shift;
    my $count = shift;
    while ($count) {
        $this->{insert} = $this->{insert} . '<br>';
        $count--;
    }
}

sub text {
    my $this = shift;
    $this->{insert} = $this->{insert} . shift . '<br/>';
}

sub title {
    my $this = shift;
    $this->{title} = shift;
}

sub modification {
    my $this    = shift;
    my $hash    = shift;
    my $replace = $hash->{replace};
    my $add     = $hash->{add};
    my $delete  = $hash->{delete};
    my $delattr = $hash->{delattr};

    my $insert = '';
    foreach ( keys %{$replace} ) {
        $insert = $insert . "replace attribute: $_ => $replace->{$_}" . '<br/>';
    }

    $insert = $insert . "Attributes to add:<br/><br/>";
    foreach ( keys %{$add} ) {
        if ( ref $add->{$_} eq "ARRAY" ) {
            foreach my $addelem ( @{ $add->{$_} } ) {
                $insert = $insert . "add attribute: $_ => $addelem" . '<br/>';
            }
        }
        else {
            $insert = $insert . "add attribute: $_ => $add->{$_}" . '<br/>';
        }
    }
    $insert = $insert . '<br/>';
    $insert = $insert . "Attributes to delete:<br/><br/>";

    foreach ( keys %{$delete} ) {
        if ( ref $delete->{delete}->{$_} eq "ARRAY" ) {
            Foswiki::Func::writeDebug("ARRAY");
            foreach my $elem ( @{ $delete->{$_} } ) {
                $insert = $insert . "delete attribute: $_ => $elem" . '<br/>';
            }
        }
        else {
            Foswiki::Func::writeDebug("SCALAR");
            $insert =
              $insert . "delete attribute: $_ => " . $delete->{$_} . '<br/>';
        }
    }
    $insert = $insert . '<br/>';
    $insert = $insert . "Attributes to delete completely:<br/><br/>";
    foreach ( @{$delattr} ) {
        $insert = $insert . "delete attribute: $_" . '<br/>';
    }

    $this->{insert} = $this->{insert} . $insert;

}

sub linkback {
    my $this  = shift;
    my $web   = shift;
    my $topic = shift;
    my $linkback =
        $Foswiki::{cfg}{DefaultUrlHost}
      . $Foswiki::{cfg}{ScriptUrlPaths}{view}
      . "/$web.$topic";

    $this->{insert} = $this->{insert}
      . a( { -href => $linkback, -target => '_self' }, "Go back" );
}

1;
