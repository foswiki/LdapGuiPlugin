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
        validOptions => {},
        validOptions => {
            'ldapguiglue'          => 'ldapguiglue',
            'ldapguiaddtogroup'    => 'ldapguiaddtogroup',
            'ldapguisubtree'       => 'ldapguisubtree',
            'ldapguitohash'        => 'ldapguitohash',
            'ldapguiaddtouserbase' => 'ldapguiaddtouserbase',
            'ldapguiignore'        => 'ldapguiignore'
        }
    };

    bless $this, $class;

    if ( $this->_parseQuery() ) {

    }
    else {
        $this->{errors}->addError(
            'ERROR_WHILE_PARSING_QUERY_FOR_OPTIONS',
            [
'There was an error while parsing the query for option parameters.',
'Note that giving no options can not be the reason of this error.',
                'check for syntax errors'
            ]
        );
    }

    #$this->_parseQueryForOptions();

    return $this;
}

=pod
---++ Private method _parseQuery ( $query ) -> $boolean

Searches the query for valid options and fills the object attributes with data.

Returns true on success, false otherwise.

=cut

sub _parseQuery {
    my $this  = shift;
    my $query = $this->{query};

    unless ( defined $query ) {
        $this->{errors}->addError( 'NO_QUERY_PASSED',
            ["No query was passed to init routine"] );
        return 0;
    }

    # if option renaming possibility gets implemented/needed validOptions just
    # needs to be replaced by a Foswiki{cfg} hash if actually someone would
    # build a schema where something collides...
    my $glueOptionName     = lc $this->{validOptions}->{'ldapguiglue'};
    my $toHashOptionName   = lc $this->{validOptions}->{'ldapguitohash'};
    my $groupAddOptionName = lc $this->{validOptions}->{'ldapguiaddtogroup'};
    my $subtreeOptionName  = lc $this->{validOptions}->{'ldapguisubtree'};
    my $ignoreOptionName   = lc $this->{validOptions}->{'ldapguiignore'};
    my $userBaseOptionName = lc $this->{validOptions}->{'ldapguiaddtouserbase'};

    #get form options hash, this does not need to be case sensitive

    my $options = {};
    foreach my $querykey ( keys $query->{param} ) {
        my $qk = lc $querykey;
        if ( exists $this->{validOptions}->{$qk} ) {

            # the query key is a valid option name
            #so push data lists to the hash foreach query key-value pair
            $options->{$qk} = $query->{param}->{$querykey};

            #foreach $dataListRef ( @{$query->{param}->{$querykey}} ) {
            #    push @{$options->{$qk}}, $dataListRef;
            #}
        }
    }

    #do we have options? No options is ok, so return 1 if none were found.
    return 1 unless ( scalar( keys %$options ) );

#if we have options, bring the data in the right form and fill data structure
#sanity checks happen later in requestData, here only the options and the right form are important
#do that for each possible valid option (because the forms could differ)

#ldapguiglue options consist only of attribute names -> result is a single list
# because it gets configured in Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGlue}
# we can do sanity checks here
#my $ldapGuiGlue = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGlue};
    if ( exists $options->{$glueOptionName} ) {
        if ( defined $options->{$glueOptionName} ) {

            if (
                $this->_parseListOption(
                    $glueOptionName, $options->{$glueOptionName}
                )
              )
            {
                $this->{glueRules} = $this->{options}->{$glueOptionName};
            }
            else {
                $this->{errors}
                  ->addError( 'ERROR_WHILE_PARSING_GLUERULES', [] );
            }
        }
        else {
            $this->{errors}->addError(
                'NO_GLUE_ATTRIBUTES_DEFINED',
                [
"No LdapGuiGlue attributes were found but the option parameter exists."
                ]
            );
        }
    }

 #ldapguitohash options have the syntax: attributename=algorithm1,algorithm2,...
 #result is hash  { attributename => [alg1, alg2, ...] }
 #also sanity checks happen later in requestdata and hash (atm)
    if ( exists $options->{$toHashOptionName} ) {
        if ( defined $options->{$toHashOptionName} ) {
            my $data   = $options->{$toHashOptionName};
            my $result = {};
            foreach (@$data) {
                my $split = [ split m/\s*=\s*/, ( lc $_ ) ];

# split result must be in the form of ['attributename','alg1,alg2,alg3,...,algN'] and not empty
                unless ( ( defined $split ) || ( scalar @$split == 2 ) ) {
                    $this->{errors}->addError( 'TOHASH_MANGLED_SYNTAX',
                        ["Wrong LdapGuiToHash syntax for expression: $_"] );
                }

                my $attributeName = lc $split->[0];
                my $algorithms = [ split m/\s*,\s*/, $split->[1] ];

                Foswiki::Func::writeDebug(
                    "TOHASH ATTR NAME: $attributeName      METHOD: $_")
                  foreach @$algorithms;

                if ($attributeName) {
                    if ( scalar @$algorithms ) {
                        $algorithms =
                          [ keys %{ { map { $_ => 1 } @$algorithms } } ];
                        $result->{$attributeName} = $algorithms;
                    }
                    else {
                        $this->{errors}->addError(
                            'TOHASH_NO_METHODS_GIVEN',
                            [
"Can not find hash method names for attribute $attributeName."
                            ]
                        );
                    }
                }

            }
            unless ( scalar keys %{$result} ) {
                $this->{errors}->addError( 'TOHASH_NO_RESULTS_FOUND',
                    ["No result could be found but the option exists."] );
                return 0;
            }
            $this->{toHash} = $result;
            $this->{options}->{$toHashOptionName} = $result;
        }
        else {
            $this->{errors}->addError(
                'NO_TOHASH_ATTRIBUTES_DEFINED',
                [
"No LdapGuiToHash attributes were found but the option parameter exists."
                ]
            );
        }
    }

#ldapguiglue options consist only of attribute names -> result is a single list
# because it gets configured in Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGlue}
# we can do sanity checks here
#my $ldapGuiGlue = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGlue};
    if ( exists $options->{$userBaseOptionName} ) {
        if ( defined $options->{$userBaseOptionName} ) {

            if (
                $this->_parseListOption(
                    $userBaseOptionName, $options->{$userBaseOptionName}
                )
              )
            {
                $this->{userBase} = $this->{options}->{$userBaseOptionName};
            }
            else {
                $this->{errors}
                  ->addError( 'ERROR_WHILE_PARSING_USERBASE_OPTION', [] );
            }
        }
        else {
            $this->{errors}->addError(
                'NO_GLUE_ATTRIBUTES_DEFINED',
                [
"No LdapGuiGlue attributes were found but the option parameter exists."
                ]
            );
        }
    }

    return 0 if $this->hasError;
    return 1;
}

=pod



=cut

sub _parseListOption {
    my $this       = shift;
    my $optionName = shift;
    my $data       = shift;

    # create a result vor optionName

    my $result = [];
    foreach (@$data) {
        my $attributes = [ split /\s*,\s*/, ( lc $_ ) ];
        $result =
          [ keys %{ { map { $_ => 1 } @$result, @$attributes } } ];    #merge
    }
    $result = [ keys %{ { map { $_ => 1 } @$result } } ]; #get rid of duplicates
    unless ( scalar @$result ) {
        $this->{errors}->addError(
            'NO_GLUE_ATTRIBUTES_FOUND',
            [
"No attributes were found but the option parameter exists and values were defined."
            ]
        );
        return 0;
    }
    $this->{options}->{$optionName} = $result;
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

sub hasToHashAttributes {
    my $this = shift;

    return 0
      unless ( defined $this->{options}->{'ldapguitohash'}
        and scalar( keys $this->{options}->{'ldapguitohash'} ) );
    return 1;
}

=pod

=cut

sub getAttributesToHash {
    my $this = shift;
    if ( $this->hasToHashAttributes() ) {
        return $this->{options}->{'ldapguitohash'};
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
