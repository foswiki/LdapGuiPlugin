package Foswiki::Plugins::LdapGuiPlugin::RequestData;

use strict;
use warnings;

use Net::LDAP::Schema;
use Foswiki::Plugins::LdapGuiPlugin::Error;
use Foswiki::Plugins::LdapGuiPlugin::Option;
use Foswiki::Plugins::LdapGuiPlugin::Hash;
use Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::Glue;

=pod

new ($error)
Either gets an error object from outside or creates its own. Initialized empty until init gets called.

=cut

sub new {
    my $class     = shift;
    my $query     = shift;
    my $option    = shift;
    my $schema    = shift;
    my $errObject = shift;
    my $ignore    = shift;

    $errObject = Foswiki::Plugins::LdapGuiPlugin::Error->new if not $errObject;
    if ( defined $ignore ) {
        unless ( ref($ignore) eq 'ARRAY' ) {
            $ignore = [];
        }
    }
    else {
        $ignore = [];
    }

    my $this = {
        ignoreAttributes => $ignore,
        schema           => undef,
        query            => undef,
        attributes       => {},
        objectClasses    => [],
        options          => {},
        other            => {},
        memberGroups     => [],
        errors           => $errObject,
        groupDN          => [],
        attributesToHash => {}

          #mode				=> ''
    };
    bless $this, $class;

    if ( ( defined $option ) && !( $option->hasError() ) ) {
        if ( defined $schema ) {
            if ( $this->init( $query, $option, $schema ) ) {
            }
            else {
                $this->{errors}->addError(
                    'CONSTRUCTOR_INIT_FAILED',
                    [
                        'Initializing request data failed at construction.',
'Something with the options, or schema retrieval went wrong.'
                    ]
                );
            }
        }
    }

    return $this;
}

=pod

init ( $schema, $query ) -> boolean

init sets the object attribites and returns true on success.
If something went wrong it returns false.
The caller of init() should control the return value. This method tries not
to die or crash the whole workflow, because this object holds either an own error object or (maybe later) just gets
a more 'global' error object passed through the constructor. It should not die but rather add
new values to the error object so that a good failure message can get rendered and returned or write it to debug files. 
Workflow should get interrupted on false return in the calling method.


TODO: split that mess up a bit + produce clean code
=cut

sub init {
    my $this          = shift;
    my $query         = shift;
    my $requestOption = shift;
    my $schema        = shift;

    #$this->{mode} = shift;
    return 0 unless ( ( defined $schema ) && ( defined $query ) );

    my $ignore        = $this->{ignoreAttributes};
    my $attributes    = {};
    my $objectClasses = ['top'];
    my $options       = {};
    my $other         = {};

    my $isIgnored = sub {
        my $subject = shift;
        my $ign     = shift;
        foreach (@$ign) {
            return 1 if ( lc $subject eq lc $_ );
        }
        return 0;
    };

    my %ldapAttributeSet;
    my @attr = $schema->all_attributes();

    foreach (@attr) {
        $ldapAttributeSet{ lc( $_->{name} ) } = undef;

        #Foswiki::Func::writeDebug("ATTRNAMES:            $_->{name}");
    }

##options can change data -> process them before the rest

    if ( defined $requestOption ) {
        return 0 if ( $this->hasError || $requestOption->hasError );
        $this->{options} = $requestOption;
        unless ( $this->_processOptions( $attributes, $ignore ) ) {
            $this->{errors}->addError( 'PROCESS_OPTIONS_FAILED',
                ['There was an error while processing options.'] );
            return 0;
        }

        $options = $this->{options}->getOptions()
          if $this->{options}->hasOptions();
    }

##//options
## getdata - messy stuff

    foreach my $requestParam ( keys( $query->{param} ) ) {
        my $paramSize = scalar @{ $query->{param}->{$requestParam} };
        if ( exists $ldapAttributeSet{ lc($requestParam) } ) {

            #it is a known LDAPattr
            if ( $isIgnored->( $requestParam, $ignore ) ) {

                #gets ignored
                my $groupMemberAttribute =
                  $Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute};
                if ( lc $requestParam eq lc $groupMemberAttribute ) {
                    push @{ $this->{memberGroups} }, $_
                      foreach ( @{ $query->{param}->{$requestParam} } );
                }
                $other->{$requestParam} = $query->{param}->{$requestParam};
            }
            elsif (lc($requestParam) eq 'objectclasses'
                or lc($requestParam) eq 'objectclass' )
            {
                #set objectclasses
                foreach ( @{ $query->{param}->{$requestParam} } ) {
                    push @$objectClasses, split( /\s*,\s*/, $_ );
                }
            }
            else
            { #it exists in the set of valid attributes, is not ignored and no objectclass... that MUST be a valid attribute
                if ( exists $this->{attributesToHash}->{ lc($requestParam) } )
                {    #should it get hashed?
                    my $hash = Foswiki::Plugins::LdapGuiPlugin::Hash->new();
                    $attributes->{$requestParam} = [];
                    if (
                        scalar
                        @{ $this->{attributesToHash}->{ lc($requestParam) } } )
                    {
                        my $methods =
                          $this->{attributesToHash}->{ lc($requestParam) };
                        foreach (@$methods) {
                            my $pw = $query->{param}->{$requestParam}[0];
                            push @{ $attributes->{$requestParam} },
                              $hash->getHash( $pw, $_ );
                        }
                    }
                    else {
                        $attributes->{$requestParam} =
                          $query->{param}->{$requestParam};
                    }
                }
                else {
                    $attributes->{$requestParam} =
                      $query->{param}->{$requestParam};
                }
            }
        }
        else {
            #it is something else, not actually needed -> for debugging purposes
            $other->{$requestParam} = $query->{param}->{$requestParam};
        }
    }

##//got it -> check it
    my $notFoundObjCl = [];

    my %obcClassLookup =
      map { $_->{name} => undef } $schema->all_objectclasses();

    foreach (@$objectClasses) {
        push( @$notFoundObjCl, $_ ) if not exists $obcClassLookup{$_};
    }

    if ( scalar @$notFoundObjCl ) {

        $this->{errors}->addError(
            'OBJECTCLASS_NOT_FOUND',
            [
'Some or all object classes could not be found. You should only get this error while adding data to the LDAP server.',
                'Not found objectClasses: ' . join( ', ', @$notFoundObjCl )
            ]
        );
    }

    #attributes dont get checked here

    unless ( $this->hasError() ) {
        $this->{attributes} = $attributes;
        $this->{attrLookup} = { map { lc($_) => $_ } keys $this->{attributes} };
        $this->{other}      = $other;
        $this->{otherLookup}   = { map { lc($_) => $_ } keys $this->{other} };
        $this->{objectClasses} = $objectClasses;

        #		$this->{options}           =      $options;
        $this->{ignoreAttributes} = $ignore;
        $this->{schema}           = $schema;
        $this->{query}            = $query;
        $this->debugWriteOut();
        return 1;
    }
    return 0;
}

=pod

private method to preprocess options before the actual requestdata gets touched.
this is because there are options which take directly influence in which request data will be ignored/constructed and so on

plannend options:


=cut

sub _processOptions {
    my $this       = shift;
    my $attributes = shift;
    return 1 unless defined $this->{options};
    my $query = $this->{options}->{query};

    if ( $this->{options}->hasToHashAttributes ) {
        $this->{attributesToHash} = $this->{options}->getAttributesToHash();
        ##do sth with this
    }

    if (   $this->{options}->hasGlueRules()
        && $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGlueAllow} )
    {    #glue option + allowed
         #$options = $this->{options}->getOptions() if $this->{options}->hasOptions();
        my $rules       = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGlue};
        my $chosenRules = $this->{options}->getRequestedGlueRules();
        unless ( $rules && $chosenRules && $query ) {
            $this->{errors}->addError( 'MISSING_PARAMS_FOR_GLUE',
                ['Parameters for glue function are missing.'] );
            return 0;
        }
        my $ldapGlue =
          Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::Glue->new( $rules,
            $chosenRules, $query, $this->{errors} );
        if ( $ldapGlue->parseRules() ) {
            if ( $ldapGlue->substitutePseudoRootNodes() ) {
                if ( $ldapGlue->isNotCylic() ) {
                    $ldapGlue->glueTogether();

                    #$ldapGlue->debugWriteOut;
                }
                else {
                    $this->{errors}->addError(
                        'FAILED_AT_CYCLICTEST',
                        [
'The LdapGuiPlugin glue rules currently defined result in cyclic (never ending) substitution'
                        ]
                    );
                }
            }
            else {
                $this->{errors}->addError( 'FAILED_AT_SUBSTITUTION',
                    ['Substitution failed.'] );
            }
        }
        else {
            $this->{errors}->addError( 'FAILED_AT_PARSE',
                ['LdapGuiPlugin glue rule parse error. Possibly wrong syntax.']
            );
        }
        unless ( $this->hasError() ) {
            foreach ( @{ $ldapGlue->{treeList} } ) {

                if ( exists $this->{attributesToHash}->{ lc( $_->{name} ) } )
                {    #should it get hashed?
                    my $hash = Foswiki::Plugins::LdapGuiPlugin::Hash->new();
                    $attributes->{ $_->{name} } = [];
                    if (
                        scalar
                        @{ $this->{attributesToHash}->{ lc( $_->{name} ) } } )
                    {
                        my $methods =
                          $this->{attributesToHash}->{ lc( $_->{name} ) }
                          ;    #use that inside the foreach
                        foreach my $method (@$methods) {
                            my $pw = $_->{value};
                            push @{ $attributes->{ $_->{name} } },
                              $hash->getHash( $pw, $method );
                        }
                    }
                    else {
                        push @{ $attributes->{ $_->{name} } }, $_->{value};
                    }
                }
                else {
                    push @{ $attributes->{ $_->{name} } }, $_->{value};
                }

                #Foswiki::Func::writeDebug(
                #    'NAME ' . $_->{name} . 'VAL ' . $_->{value} );

#unless ( $this->addAttribute($_->{name}, [$_->{value}]) ) {
#	$this->{errors}->addError('COULD_NOT_ADD_ATTRIBUTE', ["Could not add attribute: $_->{name} , value: $_->{value}"]);
#}
#push @{$this->{ignoreAttributes}}, $_->{name};
                unless ( $this->addIgnoreAttribute( [ $_->{name} ] ) ) {
                    $this->{errors}->addError(
                        'COULD_NOT_ADD_IGNOREATTRIBUTE',
                        [
"Could not add attributename to ignorelist: $_->{name}"
                        ]
                    );
                }
            }
        }

    }
    if ( $this->{options}->hasGroupsToAdd() ) {
        $this->{groupDN} = $this->{options}->getGroupDN();
    }
    if ( $this->{options}->hasSubtreeOptions() ) {
        my $userBaseAliases =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBaseAliases}
          ##do sth with this
    }

    return 0 if ( $this->hasError );
    return 1;
}

=pod


=cut

sub getAttributes {
    my $this = shift;
    return $this->{attributes};
}

=pod

=cut

sub hasAttribute {
    my $this = shift;
    my $name = shift;
    return ( exists $this->{attrLookup}->{ lc $name } );
}

=pod

=cut

sub getAttributeByName {
    my $this = shift;
    my $name = shift;
    unless ( exists $this->{attrLookup} ) {
        return undef;
    }

    if ( exists $this->{attrLookup}->{ lc $name } ) {
        my $attr = $this->{attrLookup}->{ lc $name };
        return $this->{attributes}->{$attr};
    }
    return undef;
}

=pod

=cut

sub getOtherByName {
    my $this = shift;
    my $name = shift;

    unless ( exists $this->{otherLookup} ) {
        return undef;
    }

    if ( exists $this->{otherLookup}->{ lc $name } ) {
        my $attr = $this->{otherLookup}->{ lc $name };
        return $this->{other}->{$attr};
    }
    return undef;
}

=pod

=cut

sub addAttribute {
    my $this     = shift;
    my $attrName = shift;
    my $val      = shift;
    return 0 if not $attrName;
    my $paramSize = scalar @$val;

    if ( $paramSize >= 1 ) {
        $this->{attributes}->{$attrName} = $val;
    }
    else {
        $this->{attributes}->{$attrName} = []; #attr is there but no value given
    }
    return 1;

}

=pod

=cut

sub hasMemberGroups {
    my $this = shift;
    return scalar( @{ $this->{memberGroups} } );
}

=pod

=cut

sub getMemberGroups {
    my $this = shift;
    return $this->{memberGroups};
}

=pod

=cut

sub hasGroupAttributes {
    my $this        = shift;
    my $groupIdName = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{GroupAttribute};
    if ( exists $this->{attributes}->{$groupIdName}
        and defined $this->{attributes}->{$groupIdName} )
    {
        return 1;
    }
    else {
        return 0;
    }
    return 0;
}

=pod

=cut

#getattrbyname??
sub getLoginAttribute {
    my $this               = shift;
    my $loginAttributeName = shift;

    if ( exists $this->{attributes} ) {
        if ( exists $this->{attributes}->{$loginAttributeName} ) {
            return $this->{attributes}->{$loginAttributeName}->[0];
        }
        else {
            $this->{errors}->addError( 'NO_LOGIN_ATTRIBUTE',
                ['getLoginAttribute: no loginAttribute was found'] );
            return undef;
        }
    }
    else {
        $this->{errors}->addError( 'NO_ATTRIBUTES',
            ['getLoginAttribute: no attributes where found.'] );
        return undef;
    }

    return undef;
}

sub getObjectClasses {
    my $this = shift;
    return $this->{objectClasses};
}

sub getOptions {
    my $this = shift;
    return $this->{objectClasses};
}

sub getOther {
    my $this = shift;
    return $this->{objectClasses};
}

sub getErrors {
    my $this = shift;
    return $this->{errors};
}

sub hasError {
    my $this = shift;
    return ( $this->{errors}->hasError() );
}

sub errorDump {
    my $this = shift;
    $this->{errors}->writeErrorsToDebug();
    return 1;
}

sub getGroupDN {
    my $this = shift;
    return $this->{groupDN};
}

=pod

=cut

sub setIgnoreAttributes {
    my $this = shift;
    my $ign  = shift;

    #oh this is so well made
    $this->{ignoreAttributes} = $ign;
    return 1;
}

=pod

=cut

sub addIgnoreAttribute {
    my $this      = shift;
    my $ign       = shift;
    my $paramSize = scalar @$ign;
    if ( $paramSize == 1 ) {
        my $str = $ign;
        $str =~ s/[[:space:]]+/ /g;
        $str = trimSpaces($str);
        push @{ $this->{ignoreAttributes} }, $str;
    }
    elsif ( $paramSize > 1 ) {
        foreach (@$ign) {
            my $str = $ign;
            $str =~ s/[[:space:]]+/ /g;
            $str = trimSpaces($str);
            push @{ $this->{ignoreAttributes} }, $str;
        }
    }
    else {
        return 0;
    }

    return 1;
}

=pod

=cut

sub debugWriteOut {
    my $this = shift;
    foreach ( keys $this->{attributes} ) {
        Foswiki::Func::writeDebug("KEY REQUESTDATA ATTRIBUTES:   $_");
        foreach my $val ( $this->{attributes}->{$_} ) {
            if ( scalar @$val ) {
                foreach my $all (@$val) {
                    Foswiki::Func::writeDebug("KEY: $_    VAL: $all");
                }
            }
            else {
                Foswiki::Func::writeDebug("KEY: $_     VAL: $val");
            }
        }
    }
    foreach ( @{ $this->{objectClasses} } ) {
        Foswiki::Func::writeDebug("KEY REQUESTDATA OBJECTCLASSES:   $_");
    }
    foreach ( keys $this->{options}->getOptions() ) {
        Foswiki::Func::writeDebug("KEY REQUESTDATA OPTIONS:   $_");
    }
    foreach ( keys $this->{other} ) {
        Foswiki::Func::writeDebug("KEY REQUESTDATA OTHER:   $_");
        foreach my $val ( $this->{other}->{$_} ) {
            if ( scalar @$val ) {
                foreach my $all (@$val) {
                    Foswiki::Func::writeDebug("KEY: $_    VAL: $all");
                }
            }
            else {
                Foswiki::Func::writeDebug("KEY: $_     VAL: $val");
            }
        }
    }
    $this->{errors}->writeErrorsToDebug();
    return 1;
}

sub getContent {
    my $this       = shift;
    my $attributes = $this->{attributes};
    my $content    = '';
    use URI::Escape;
    foreach my $key ( keys %{$attributes} ) {
        foreach my $data ( @{ $attributes->{$key} } ) {
            $key     = uri_escape($key);
            $data    = uri_escape($data);
            $content = $content . $key . '=' . $data . '&';
        }
    }
    $content =~ s/&$//;
    Foswiki::Func::writeDebug("CONTENT: $content");
    return $content;
}

###push that to util or sth
sub trimSpaces {
    my $s = shift;
    return if !$s;
    $s =~ s/^[[:space:]]+//s;    # trim at start
    $s =~ s/[[:space:]]+$//s;    # trim at end
    return $s;
}

1;
