package Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::RootNode;

use strict;
use warnings;

use Foswiki::Plugins::LdapGuiPlugin::Error;

=pod

new ($error)
Either gets an error object from outside or creates its own. Initialized empty until init gets called.

=cut

sub new {
    my $class           = shift;
    my $name            = shift;
    my $childNodes      = shift;
    my $delimiters      = shift;
    my $formatFunctions = shift;
    my $errObject       = shift;

    unless ( defined( $name && $childNodes ) ) {
        return undef;
    }

    unless ( scalar @$childNodes ) {
        Foswiki::Func::writeDebug("NO CHILDNODES FOR $name");
    }

    $errObject = Foswiki::Plugins::LdapGuiPlugin::Error->new if not $errObject;

    if ( not scalar @$formatFunctions ) {    #if no formatfunctions -> pass id
        push @$formatFunctions, sub {
            my $string = shift;
            return $string;
        };
    }

    $delimiters = '' unless $delimiters;

    my $this = {
        name           => $name,
        type           => 'root',
        children       => $childNodes,
        errors         => $errObject,
        value          => '',
        formatFunction => $formatFunctions,
        delimiters     => $delimiters
    };

    bless $this, $class;
    return $this;
}

=pod

=cut

sub appendValue {
    my $this = shift;
    my $val  = shift;
    unless ($val) {
        $this->{errors}->addError( 'NO_VALUE',
            ["$this->{name} got no value passed to append"] );
    }

    #Foswiki::Func::writeDebug("ROOTNODE: $this->{name}");
    #Foswiki::Func::writeDebug("ROOTNODE VALUE BEFORE: $this->{value}");
    $this->{value} = $this->{value} . $val;

    #Foswiki::Func::writeDebug("ROOTNODE: $this->{name}");
    #Foswiki::Func::writeDebug("ROOTNODE VALUE AFTER: $this->{value}");
    return 1;

}

=pod

=cut

sub applyFormat {
    my $this            = shift;
    my $formatFunctions = $this->{formatFunction};
    my $val             = $this->{value};
    unless ( defined $formatFunctions ) {
        return $val;
    }

    foreach my $f (@$formatFunctions) {
        $val = $f->($val);
    }

    return $val;

}

=pod

=cut

sub setValue {
    my $this = shift;
    my $val  = shift;
    $this->{value} = $val;
    return 1;
}

=pod

=cut

sub getValue {
    my $this  = shift;
    my $value = $this->{value};
    if ($value) {
        foreach my $f ( @{ $this->{formatFunction} } ) {
            $value = $f->($value);
        }
    }
    return $value . $this->{delimiter};
}

=pod

=cut

sub printdebug {
    my $this = shift;
    Foswiki::Func::writeDebug( "NODE\{$this->{name}\}"
          . '(VAL: '
          . $this->{value}
          . ', TYPE: '
          . $this->{type}
          . ')' );
}

=pod

=cut

sub getChildren {
    my $this = shift;
    return $this->{children};
}

1;
