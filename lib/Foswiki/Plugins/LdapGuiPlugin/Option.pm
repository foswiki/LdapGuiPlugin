package Foswiki::Plugins::LdapGuiPlugin::Option;

use strict;
use warnings;

use Net::LDAP qw(LDAP_REFERRAL);
use Net::LDAP::Extension::SetPassword;
use Net::LDAP::Entry;
use Net::LDAP::LDIF;
use Net::LDAP::Schema;
use Foswiki::Plugins::LdapGuiPlugin::Error;

=pod

new ($error)
Either gets an error object from outside or creates its own. Initialized empty until init gets called.

=cut

sub new {
    my $class = shift;
    my $query = shift;
    return undef if not $query;

    my $errObject = shift;

    $errObject = Foswiki::Plugins::LdapGuiPlugin::Error->new if not $errObject;

    my $this = {
        query        => $query,
        options      => {},
        errors       => $errObject,
        validOptions => {
            'ldapguiglue'          => undef,
            'ldapguiaddtogroup'    => undef,
            'ldapguisubtree'       => undef,
            'ldapguiaddtouserbase' => undef
        }
    };

    bless $this, $class;

    $this->_parseQueryForOptions();

    return $this;
}

sub _parseQueryForOptions {
    my $this  = shift;
    my $query = $this->{query};

    unless ( defined $query ) {
        $this->{errors}->addError( 'NO_QUERY_PASSED',
            ["No query was passed to init routine"] );
        return 0;
    }

    return 1 unless defined( $this->{query}->{param}->{option} );

    my $optList = [];
    if ( @{ $this->{query}->{param}->{option} } )
    {    #see if options are present in the form request
        my $optCount = scalar @{ $query->{param}->{option} };
        if ( $optCount > 0 ) {
            if ( $optCount == 1 ) {
                $optList = [ split( /\s*,\s*/, $query->{param}->{option}[0] ) ];
            }
            else {
                push( @$optList, trimSpaces($_) )
                  foreach @{ $query->{param}->{option} };
            }
        }
    }

    foreach my $option (@$optList)
    {    #fill options hash with valid options (those options we expect)
            #Foswiki::Func::writeDebug("optionsc: $option");
        my ( $o, $v ) = split( /\s*=\s*/, $option );

        #Foswiki::Func::writeDebug("optionsc: $o     =     $v");
        $this->addOption( $o, $v );
    }

    foreach my $k ( keys $this->{options} ) {
        Foswiki::Func::writeDebug("OPT: $k");
        Foswiki::Func::writeDebug("PARAM: $_")
          foreach ( @{ $this->{options}->{$k} } );
    }

    return 1;
}

=pod

=cut

sub addOption {
    my $this   = shift;
    my $option = shift;
    my $value  = shift;
    unless ($option) {
        $this->{errors}
          ->addError( 'NO_OPTION', ['found no option on addOption() call'] );
        return 0;
    }
    unless ($value) {
        $this->{errors}
          ->addError( 'NO_VALUE_FOR_OPTION', ["No value found for $option"] );
    }

    if ( exists $this->{validOptions}->{$option} ) {
        push @{ $this->{options}->{$option} }, $value;
    }
    else {

        #$errors->{'INVALID_OPTION'} = "$o is not a valid option.";
        $this->{errors}
          ->addError( 'INVALID_OPTION', ["$option is not a valid option."] );
        return 0;
    }
    return 1;
}

=pod

=cut

sub hasSubtrees {
    my $this = shift;
    return ( exists $this->{options}->{'ldapguiaddtouserbase'}
          and scalar @{ $this->{options}->{'ldapguiaddtouserbase'} } );
}

=pod

=cut

sub getSubtrees {
    my $this = shift;

    #return [] if (not $this->hasSubtrees());
    my $userBaseAliases =
      $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBaseAliases};
    my $userBases = [];
    foreach my $userBase ( keys %$userBaseAliases ) {
        foreach ( @{ $this->{options}->{'ldapguiaddtouserbase'} } ) {
            if ( lc $_ eq lc $userBase ) {
                push @$userBases, $userBaseAliases->{$_};
            }
            else {
                $this->{errors}->addError( 'USERBASE_ALIAS_NOT_FOUND',
                    ["Alias $_ is not existing in configuration."] );
                return [];
            }
        }
    }
    return $userBases;
}

=pod

=cut

sub getGroupDN {
    my $this = shift;

    my $groupAliases =
      $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGroupIdentifier};
    my $groupDN = [];

    foreach ( @{ $this->{options}->{'ldapguiaddtogroup'} } ) {
        my $found = 0;
        foreach my $groupName ( keys %$groupAliases ) {
            $found = 0;
            if ( lc $_ eq lc $groupName ) {
                push @$groupDN, $groupAliases->{$_};
                $found++;
                last;
            }
        }
        if ( not $found ) {
            $this->{errors}->addError( 'GROUPALIAS_NOT_FOUND',
                ["Alias $_ is not existing in configuration."] );
            return [];
        }
    }
    return $groupDN;
}

=pod

=cut

sub hasGroupsToAdd {
    my $this = shift;
    return ( exists $this->{options}->{'ldapguiaddtogroup'} ) ? 1 : 0;
}

=pod

=cut

sub hasSubtreeOptions {
    my $this = shift;

    return 0;
}

=pod

=cut

sub hasGlueRules {
    my $this = shift;
    return ( exists $this->{options}->{'ldapguiglue'} );
}

=pod

=cut

sub getRequestedGlueRules {
    my $this = shift;
    if ( $this->hasGlueRules() ) {
        return $this->{options}->{'ldapguiglue'};
    }
    return {};
}

=pod

=cut

sub hasAttributeHashOptions {
    my $this = shift;

#return scalar ( keys $this->{options}->{'ldapguihashattr'} ) if defined $this->{options}->{'ldapguihashattr'};
    return 0;
}

=pod

=cut

sub getAttributesToHash {
    my $this = shift;
    if ( $this->hasAttributeHashOptions() ) {
        return $this->{options}->{'ldapguihashattr'};
    }
    return {};
}

=pod

=cut

sub getOptions {
    my $this = shift;
    return $this->{options};
}

=pod

=cut

sub hasOptions {
    my $this = shift;
    return scalar( keys $this->{options} ) > 0;
}

=pod

=cut

sub hasError {
    my $this = shift;
    return ( $this->{errors}->hasError() );
}

1;

