package Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::Node;

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
    my $delimiters      = shift;
    my $formatFunctions = shift;
    my $errObject       = shift;

    return undef unless ($name);

    $delimiters = '' unless $delimiters;

    if ( not scalar @$formatFunctions ) {    #if no formatfunctions -> pass id
        push @$formatFunctions, sub {
            my $string = shift;
            return $string;
        };
    }

    $errObject = Foswiki::Plugins::LdapGuiPlugin::Error->new if not $errObject;

    my $this = {
        name           => $name,
        type           => 'node',
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

sub getValue {
    my $this = shift;
    return $this->{value};
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
    my $this  = shift;
    my $value = shift;
    return 0 unless $value;
    foreach my $f ( @{ $this->{formatFunction} } ) {
        $value = $f->($value);
    }
    $this->{value} = $value . $this->{delimiter};
    return 1;
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

1;
