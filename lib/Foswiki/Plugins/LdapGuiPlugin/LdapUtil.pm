package Foswiki::Plugins::LdapGuiPlugin::LdapUtil;

use strict;
use warnings;

use Net::LDAP qw(LDAP_REFERRAL);
use Net::LDAP::Extension::SetPassword;
use Net::LDAP::Entry;
use Net::LDAP::LDIF;
use Net::LDAP::Schema;
use Net::LDAP::Filter;
use Foswiki::Plugins::LdapGuiPlugin::Error;

=pod

---++ ClassMethod new ($errorObject)

Either gets an error object from outside or creates its own. Initializes itself

=cut

sub new {
    my $class     = shift;
    my $errObject = shift;

    $errObject = Foswiki::Plugins::LdapGuiPlugin::Error->new if not $errObject;

    #### LDAP server configuration, if LDAPContrib is installed -> use its configuration
    #### TODO: maybe LdapContrib should be a dependency
    my $ServerHost            = '';
    my $ServerVersion         = '';
    my $Port                  = '';
    my $BaseDN                = '';
    my $UserBase              = '';
    my $LoginAttribute        = '';
    my $MailAttribute         = '';
    my $WikiNameAttributes    = '';
    my $GroupBase             = '';
    my $AllowGroupBaseAliases = '';
    my $Exclude               = '';

    my $charSet = '';
    my $useSASL;
    my $saslMechanism;
    my $useTLS;
    my $tlsSSLVersion;
    my $tlsVerify;
    my $tlsCAPath;
    my $tlsCAFile;
    my $tlsClientCert;
    my $tlsClientKey;

    if ( ( scalar( keys %{ $Foswiki::cfg{Ldap} } ) )
        and $Foswiki::cfg{Ldap}{Host} )
    {
        $ServerHost         = $Foswiki::cfg{Ldap}{Host};
        $ServerVersion      = $Foswiki::cfg{Ldap}{Version};
        $Port               = $Foswiki::cfg{Ldap}{Port};
        $BaseDN             = $Foswiki::cfg{Ldap}{Base};
        $UserBase           = $Foswiki::cfg{Ldap}{UserBase};
        $LoginAttribute     = $Foswiki::cfg{Ldap}{LoginAttribute};
        $MailAttribute      = $Foswiki::cfg{Ldap}{MailAttribute};
        $WikiNameAttributes = $Foswiki::cfg{Ldap}{WikiNameAttributes};
        $GroupBase          = $Foswiki::cfg{Ldap}{GroupBase};
        $Exclude            = $Foswiki::cfg{Ldap}{Exclude};

        $charSet       = $Foswiki::cfg{Ldap}{CharSet};
        $useSASL       = $Foswiki::cfg{Ldap}{UseSASL};
        $saslMechanism = $Foswiki::cfg{Ldap}{SASLMechanism};
        $useTLS        = $Foswiki::cfg{Ldap}{UseTLS};
        $tlsSSLVersion = $Foswiki::cfg{Ldap}{TLSSSLVersion};
        $tlsVerify     = $Foswiki::cfg{Ldap}{TLSVerify};
        $tlsCAPath     = $Foswiki::cfg{Ldap}{TLSCAPath};
        $tlsCAFile     = $Foswiki::cfg{Ldap}{TLSCAFile};
        $tlsClientCert = $Foswiki::cfg{Ldap}{TLSClientCert};
        $tlsClientKey  = $Foswiki::cfg{Ldap}{TLSClientKey};

    }
    else {
        $ServerHost = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiServerHost};
        $ServerVersion =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiServerVersion};
        $Port     = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiPort};
        $BaseDN   = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBaseDN};
        $UserBase = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBase};
        $LoginAttribute =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiLoginAttribute};
        $MailAttribute =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiMailAttribute};
        $WikiNameAttributes =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiWikiNameAttributes};
        $GroupBase = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGroupBase};
        $Exclude   = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiExclude};

        $charSet = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiCharSet};
        $useSASL = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUseSASL};
        $saslMechanism =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiSASLMechanism};
        $useTLS = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUseTLS};
        $tlsSSLVersion =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSSSLVersion};
        $tlsVerify = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSVerify};
        $tlsCAPath = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSCAPath};
        $tlsCAFile = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSCAFile};
        $tlsClientCert =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSClientCert};
        $tlsClientKey =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSClientKey};
    }

    my $this = {
        ldap        => undef,
        isConnected => 0,
        schema      => undef,

        #shared attributes with LdapContrib marked with _
        host           => $ServerHost,
        port           => $Port,
        version        => $ServerVersion,
        baseDN         => $BaseDN,
        userBase       => $UserBase,
        loginAttribute => $LoginAttribute,
        mailAttribute  => $MailAttribute,
        groupBase      => $GroupBase,
        exclude        => $Exclude,
        charSet        => $charSet,
        useSASL        => $useSASL,
        saslMechanism  => $saslMechanism,
        useTLS         => $useTLS,
        tlsSSLVersion  => $tlsSSLVersion,
        tlsVerify      => $tlsVerify,
        tlsCAPath      => $tlsCAPath,
        tlsCAFile      => $tlsCAFile,
        tlsClientCert  => $tlsClientCert,
        tcsClientKey   => $tlsClientKey,

        #util data
        objectClasses       => [],
        objectClassLookup   => {},
        objectClassLookupLC => {},
        attributes          => [],
        attributeLookup     => {},
        attributeLookupLC   => {},
        errors              => $errObject
    };
    bless $this, $class;

    #getting the schema won't hurt
    if ( $this->ldapConnect() ) {
        if ( $this->isConnected ) {
            if ( defined $this->{ldap} ) {
                $this->{schema} = $this->{ldap}->schema();
                $this->ldapDisconnect();
            }
            else {
                $this->{errors}->addError( 'NO_DEFINED_LDAP_OBJECT',
                    ['No Ldap object was established'] );
            }
        }
        else {
            $this->{errors}->addError( 'NOT_CONNECTED_TO_LDAP',
                ['Connect succeeded but not connected'] );
        }
    }
    else {
        $this->{errors}
          ->addError( 'NOT_CONNECTED_TO_LDAP', ['Connect failed'] );
    }

    unless ( defined $this->{schema} ) {
        $this->{errors}->addError(
            'NO_SCHEMA',
            [
                'LdapUtil::new($schema[,$Error[,$ldap])',
'No ldap object and no schema was passed to the constructor. No raw data.'
            ]
        );
    }

    if ( not $this->init() ) {
        $this->{errors}->addError(
            'INIT_FAILED',
            [
                'LdapUtil::new($schema[,$Error[,$ldap])',
                'Initialization failed.'
            ]
        );
    }

    return $this;
}

=pod

ldapSearch ( %args ) -> $search

Performs a search with in %args specified arguments.
Check $this->hasError or the associated $error object for errors afterwards or control the search object.

=cut

sub ldapSearch {
    my $this = shift;
    my $args = shift;
    unless ( $this->ldapConnect() ) {
        $this->{errors}->addError(
            'SEARCH_FAILED_ON_CONNECT',
            [
'Search failed by trying to bind anonymously. Read the error log.'
            ]
        );
    }
    my $search;
    if ( $this->{isConnected} ) {
        $search = $this->{ldap}->search(%$args);
    }
    else {
        $this->{errors}->addError( 'UNKNOWN_ERROR_ON_CONNECT',
            ['LdapSearch: unknown error on connect'] );
        die;
    }
    $this->ldapDisconnect();

    #Foswiki::Func::writeDebug( "SC: " . $search->count() );
    return $search;
}

=pod
---++ ObjectMethod ldapAddToGroup ( $bindDN, $password, \@groupDN, \%modifyHash ) -> $boolean

Takes a dn, password, list of group dn and a modify hash, binds to the LDAP and modifys the groups in groupDN by adding the member defined in the hash.

Use this function to add a user to a list of groups.

returns 1 on success, 0 otherwise. so check the return value or $error->hasError for error checking.

=cut

sub ldapAddToGroup {
    my $this     = shift;
    my $bindDN   = shift;
    my $password = shift;
    my $groupDN  = shift;
    my $addHash  = shift;

    unless ( defined $bindDN and $bindDN ) {
        $this->{errors}->addError( 'ADD_TO_GROUP_NO_USER',
            ['ldapAddToGroup: No bind dn was passed to LdapAdd'] );
    }
    unless ( defined $password and $password ) {
        $this->{errors}->addError( 'ADD_TO_GROUP_NO_PASSWORD',
            ['ldapAddToGroup: No password was passed to LdapAdd'] );
    }
    unless ( scalar @$groupDN ) {
        $this->{errors}->addError( 'ADD_TO_GROUP_NO_ENTRY',
            ['ldapAddToGroup: No group dn where passed.'] );
    }
    unless ( defined $addHash ) {
        $this->{errors}->addError( 'ADD_TO_GROUP_NO_ENTRY',
            ['ldapAddToGroup: No group dn where passed.'] );
    }

    if ( $this->hasError() ) {
        return 0;
    }

    if ( $this->ldapConnect( $bindDN, $password ) ) {
        if ( $this->{isConnected} ) {
            unless ( defined $this->{ldap} ) {
                $this->{errors}->addError( 'NOT_DEFINED_LDAP_OBJECT',
                    ['ldapAddToGroup: No LDAP object after connect.'] );
                $this->ldapDisconnect();
                return 0;
            }
            foreach (@$groupDN) {

#Foswiki::Func::writeDebug("$_      $groupMemberAttribute        $attributes->{$loginAttr}->[0]");
                my $mesg = $this->{ldap}->modify( $_, add => $addHash );

                if ( $mesg->is_error() ) {
                    my $errorMessage = $mesg->error();
                    $this->{errors}->addError(
                        'ERROR_ON_ADD_TO_GROUP',
                        [
                            "ldapAddToGroup: Error on add to $_:",
                            $errorMessage
                        ]
                    );
                }
            }

            #password is set?
        }
        else {
            $this->{errors}->addError( 'UNKNOWN_ERROR_ON_CONNECT',
                ['ldapAddToGroup: unknown error on connect'] );
            $this->ldapDisconnect();
            return 0;
        }
    }
    else {
        $this->ldapDisconnect();
        return 0;
    }

    $this->ldapDisconnect();
    return 1;

}

=pod

---++ ObjectMethod ldapAdd ( $user, $subtree, $password, $entry ) -> $boolean

Adds a new entry to the LDAP DIT. For this action a user (bind DN) and password is needed.
Returns true on success, false otherwise. Check $this-hasError on false return.
Attention: this method does not check if you wand to use a proxy user, providing correct data is specified 

=cut

sub ldapAdd {
    my $this     = shift;
    my $bindDN   = shift;
    my $password = shift;
    my $entry    = shift;

    unless ( defined $bindDN and $bindDN ) {
        $this->{errors}->addError( 'LDAPADD_NO_USER',
            ['ldapAdd: No bind dn was passed to LdapAdd'] );
    }
    unless ( defined $password and $password ) {
        $this->{errors}->addError( 'LDAPADD_NO_PASSWORD',
            ['ldapAdd: No password was passed to LdapAdd'] );
    }
    unless ( defined $entry ) {
        $this->{errors}
          ->addError( 'LDAPADD_NO_ENTRY', ['ldapAdd: No entry was passed.'] );
    }
    if ( $this->hasError() ) {
        return 0;
    }

    if ( $this->ldapConnect( $bindDN, $password ) ) {
        if ( $this->{isConnected} ) {
            unless ( defined $this->{ldap} ) {
                $this->{errors}->addError( 'NOT_DEFINED_LDAP_OBJECT',
                    ['LdapAdd: No LDAP object after connect.'] );
                $this->ldapDisconnect();
                return 0;
            }

            my $result = $this->{ldap}->add($entry);

            #password is set?
            if ( $result->is_error() ) {
                my $errorMessage = $result->error();
                $this->{errors}->addError( 'ERROR_ON_ADD',
                    [ 'LdapAdd: Error on add:', $errorMessage ] );
            }

        }
        else {
            $this->{errors}->addError( 'UNKNOWN_ERROR_ON_CONNECT',
                ['LdapAdd: unknown error on connect'] );
            return 0;
        }
    }
    else {
        return 0;
    }

    $this->ldapDisconnect();
    return 0 if $this->hasError();
    return 1;

}

=pod

---++ ObjectMethod ldapModifyReplace ( $bindDN, $password, $dn, \%replaceHash ) -> $boolean

Modify the dn passed in $dn with the replaceHash. This overwrites data and the user specified in bindDN must have write access to $dn.

return 1 on success, 0 otherwise so check the return value or $error->hasError for error checking.

=cut

sub ldapModifyReplace {
    my $this     = shift;
    my $bindDN   = shift;
    my $password = shift;
    my $dn       = shift;
    my $replace  = shift;

    unless ( defined $bindDN and $bindDN ) {
        $this->{errors}->addError( 'LDAPMODIFY_NO_USER',
            ['ldapModifyReplace: No bind dn was passed to LdapAdd'] );
    }
    unless ( defined $password and $password ) {
        $this->{errors}->addError( 'LDAPMODIFY_NO_PASSWORD',
            ['ldapModifyReplace: No password was passed to LdapAdd'] );
    }
    unless ( defined $dn ) {
        $this->{errors}->addError( 'LDAPMODIFY_NO_ENTRY',
            ['ldapModifyReplace: No target dn was passed.'] );
    }
    unless ( defined $replace ) {
        $this->{errors}->addError( 'LDAPMODIFY_NO_ENTRY',
            ['ldapModifyReplace: No replace hash was passed.'] );
    }
    if ( $this->hasError() ) {
        return 0;
    }

    if ( $this->ldapConnect( $bindDN, $password ) ) {
        if ( $this->{isConnected} ) {
            unless ( defined $this->{ldap} ) {
                $this->{errors}->addError( 'NOT_DEFINED_LDAP_OBJECT',
                    ['ldapModifyReplace: No LDAP object after connect.'] );
                $this->ldapDisconnect();
                return 0;
            }

            my $result = $this->{ldap}->modify( $dn, replace => {%$replace} );

            if ( $result->is_error() ) {
                my $errorMessage = $result->error();
                $this->{errors}->addError( 'ERROR_ON_MODIFY',
                    [ 'ldapModifyReplace: Error on add:', $errorMessage ] );
            }

        }
        else {
            $this->{errors}->addError( 'UNKNOWN_ERROR_ON_CONNECT',
                ['ldapModifyReplace: unknown error on connect'] );
            return 0;
        }
    }
    else {
        return 0;
    }

    $this->ldapDisconnect();
    return 0 if $this->hasError();
    return 1;
}

=pod

---++ ObjectMethod getModifyReplaceHash ( $Net::Ldap::Entry, \%data ) -> \%replaceHash

Takes the entry and compares the data in $data to build a replace hash ready to throw into LdapModifyReplace as an argument.

=cut

sub getModifyReplaceHash {
    my $this    = shift;
    my $entry   = shift;
    my $data    = shift;
    my $modHash = {};
    return 0 unless ( defined $entry );
    unless ( defined $data ) {
        $data = $this->{attributes};
    }
    foreach my $key (%$data) {
        my $formDataSize = 1;

        #Foswiki::Func::writeDebug("K: $key");
        #Foswiki::Func::writeDebug("SIZE: $formDataSize");
        if ( $entry->exists($key) ) {
            my @entryValues = $entry->get_value($key);

            #we have an attribute for the formkey
            if (@entryValues) {

                #entry has already values for key. check if we have some too
                if ( @{ $data->{$key} } ) {

                    #check if we just need a string
                    if ( ( @{ $data->{$key} } == 1 ) && ( @entryValues == 1 ) )
                    {

                     #now we just need a string, check if something will changes
                        if ( $data->{$key}->[0] eq $entryValues[0] ) {

                            #nothing to do here
                        }
                        else {

                            #change
                            $modHash->{$key} = $data->{$key}->[0];
                        }
                    }
                    else {

                   #here we need an array ref. ATTENTION: Empty Array = deleting
                        $modHash->{$key} = $data->{$key};
                    }
                }
                else {

                    #we dont have values to modify
                }
            }
            else {

                #entry has no values yet, but the attribute is existing
                if ( @{ $data->{$key} } == 1 ) {
                    $modHash->{$key} = $data->{$key}->[0];
                }
                else {
                    $modHash->{$key} = $data->{$key};
                }
            }
        }
        else {

           #fail -> for Form key attr. there is not value in original LDAP entry
        }

    }

    return $modHash;

}

=pod
---++ ObjectMethod ldapConnect ( $dn , $password ) -> $boolean

This is more or less the LDAPContrib connect()
Difference is that the caller has to check if proxy users are used und to provide the
correct dn and password

=cut

sub ldapConnect {
    my $this   = shift;
    my $dn     = shift;
    my $passwd = shift;
    my $ldap   = undef;

    $ldap = Net::LDAP->new(
        $this->{host},
        port    => $this->{port},
        version => $this->{version},
    );
    unless ( defined $ldap ) {
        $this->{errors}->addError( 'FAILED_TO_CONNECT',
            [ "failed to connect to $this->{host}", "Additional: $@" ] )
          if defined $this->{errors};
        return 0;
    }
    my $msg;

    # TLS bind
    if ( $this->{useTLS} ) {

        #writeDebug("using TLS");
        my %args = (
            verify => $this->{tlsVerify},
            cafile => $this->{tlsCAFile},
            capath => $this->{tlsCAPath},
        );
        $args{"clientcert"} = $this->{tlsClientCert} if $this->{tlsClientCert};
        $args{"clientkey"}  = $this->{tlsClientKey}  if $this->{tlsClientKey};
        $args{"sslversion"} = $this->{tlsSSLVersion} if $this->{tlsSSLVersion};
        $msg                = $ldap->start_tls(%args);
        $this->{errors}->addError( 'START_TLS_ERROR', [ $msg->{errorMessage} ] )
          if ( exists $msg->{errorMessage} and defined $this->{errors} );
    }
    use Encode ();
    $passwd = Encode::decode( $this->{charSet}, $passwd ) if $passwd;

    #auth by dn
    if ( defined($dn) ) {
        unless ( defined($passwd) ) {

            # no password -> error
            $this->{errors}
              ->addError( 'ILLEGAL_CALL_TO_CONNECT', ['No password.'] )
              if defined $this->{errors};
            return 0;
        }

        if ( $this->{useSASL} ) {

            # sasl bind
            my $sasl = Authen::SASL->new(
                mechanism => $this->{saslMechanism}
                ,    #'DIGEST-MD5 PLAIN CRAM-MD5 EXTERNAL ANONYMOUS',
                callback => {
                    user => $dn,
                    pass => $passwd,
                },
            );

            #Foswiki::Func::writeDebug("sasl bind to $dn");
            $msg =
              $ldap->bind( $dn, sasl => $sasl, version => $this->{version} );
        }
        else {

            #simple bind
            $msg = $ldap->bind( $dn, password => $passwd );
        }
    }
    else {

        #anon bind
        $msg = $ldap->bind();
    }

    if ( $msg->is_error() ) {
        my $errorMessage = $msg->error();
        $this->{errors}
          ->addError( 'COULD_NOT_BIND_TO_LDAP_SERVER', ["$errorMessage"] )
          if defined $this->{errors};
        return 0;
    }

    $this->{ldap}        = $ldap;
    $this->{isConnected} = 1;
    return 1;

}

=pod
---++ ObjectMethod ldapDisconnect ( ) -> 1

basically like ldapContrib disconnect()

=cut

sub ldapDisconnect {
    my $this = shift;
    return 0 unless defined $this->{ldap};
    $this->{ldap}->unbind;
    $this->{ldap}        = undef;
    $this->{isConnected} = 0;
    return 1;

}

=pod
---++ ObjectMethod isConnected() -> $boolean

returns true if a connection to the LDAP server is established, false otherwise.

=cut

sub isConnected {
    my $this = shift;
    return $this->{isConnected};
}

=pod
---++ ObjectMethod init () -> $boolean

Init starts _initObjectClasses and _initAttributes and returns true of both succeeded.
The initialization is mostly about tool function and to easy the work with the attributes.
This method is invoked in the constructor if the ldap schema of the server was retrieved and a first initial connect succeeded so in this case the object is already initialized.
But you are able to initialize later manually too.

=cut

sub init {
    my $this = shift;
    return ( _initObjectClasses($this) && _initAttributes($this) );
}

=pod
_initObjectClasses ( ) -> $boolean

Initalizes some lookup hashes which could be retrieved later if the LDAP schema is defined. 

=cut

sub _initObjectClasses {
    my $this = shift;
    if ( not defined $this->{schema} ) {
        $this->{errors}
          ->addError( 'NO_LDAP_SCHEMA', ['No LDAP schema was passed'] );
        return 0;
    }
    my $objectClassSet   = {};
    my $objectClassSetLC = {};
    my $objectClasses    = [ $this->{schema}->all_objectclasses() ];
    unless ( scalar @$objectClasses ) {
        $this->{errors}->addError(
            'NO_LDAP_OBJECTCLASSES',
            [
                'Can not retrieve objectClasses from the LDAP schema',
'Maybe your connection setting are wrong or no LDAP object where passed to the constructor.'
            ]
        );
        return 0;
    }
    foreach (@$objectClasses) {
        $objectClassSet->{$_} = undef;
        $objectClassSetLC->{ lc $_ } = undef;
    }
    $this->{objectClasses}       = $objectClasses;
    $this->{objectClassLookup}   = $objectClassSet;
    $this->{objectClassLookupLC} = $objectClassSetLC;
    return 1;

}

=pod
_initAttributes ( ) -> $boolean

Initalizes some lookup hashes which could be retrieved later if the LDAP schema is defined. 
=cut

sub _initAttributes {
    my $this = shift;
    if ( not defined $this->{schema} ) {
        $this->{errors}
          ->addError( 'NO_LDAP_SCHEMA', ['No LDAP schema was passed'] );
        return 0;
    }
    my $attributeSet   = {};
    my $attributeSetLC = {};
    my $attributes     = [ $this->{schema}->all_attributes() ];
    unless ( scalar @$attributes ) {
        $this->{errors}->addError(
            'NO_LDAP_ATTRIBUTES',
            [
                'Can not retrieve attributes from the LDAP schema',
'Maybe your connection setting are wrong or no LDAP object where passed to the constructor.'
            ]
        );
        return 0;
    }
    foreach (@$attributes) {
        $attributeSet->{ $_->{name} } = undef;
        $attributeSetLC->{ lc $_->{name} } = undef;
    }
    $this->{Attributes}        = $attributes;
    $this->{attributeLookup}   = $attributeSet;
    $this->{attributeLookupLC} = $attributeSetLC;
    return 1;
}

=pod

---++ ObjectMethod isUniqueLdapAttribute ( $attributeName, $value ) -> boolean

searches inside the userBase if the attributevalue for a specific attribute is already inside the LDAP
returns true if it is already there, false otherwise and on failure (check if error)

=cut

sub isUniqueLdapAttribute {
    my $this          = shift;
    my $attributeName = shift;
    my $value         = shift;
    Foswiki::Func::writeDebug($attributeName);
    unless ( defined $attributeName and defined $value ) {
        return 0;
    }
    $attributeName = trimSpaces($attributeName);
    my $userBase = $this->{userBase} if defined( $this->{userBase} );
    foreach my $base (@$userBase) {

        #my $filter = Net::LDAP::Filter->new( "uidNumber=$value" );
        my $args = {
            base   => $base,
            scope  => 'sub',
            filter => "$attributeName=$value",
            attrs  => ['1.1']
        };

        my $result = $this->ldapSearch($args);
        if ( $result->is_error() ) {
            $this->{errors}->addError( 'ERROR_WHILE_SEARCHING',
                [ "Search for $attributeName=$value failed", $result->error() ]
            );
            return undef;
        }
        if ( $result->count() ) {
            return 0;
        }
    }

    return 1;
}

=pod

---++ ObjectMethod getLastUidnumberFromLDAP ( $attributeName ) -> $number

gets the biggest positive value of the numerical attribute.
do not call this on attributes which:
   * are not numerical
   * can be negative

=cut

sub getLastUidnumberFromLDAP {
    my $this          = shift;
    my $attributeName = shift;
    my $userBase      = $this->{userBase} if defined( $this->{userBase} );
    unless ( scalar @$userBase && $attributeName ) {
        $this->{errors}->addError(
            'MISSING_PARAMETERS',
            [
'getLastUidnumberFromLDAP: Please call this function with an attribute name and make sure the object is initialized correctly'
            ]
        );
        return -1;
    }
    $attributeName = trimSpaces($attributeName);
    my $ret = -1;
    foreach my $base (@$userBase) {

        #my $filter = Net::LDAP::Filter->new( 'uidnumber=*' );
        my $args = {
            base   => $base,
            scope  => 'sub',
            filter => "$attributeName=*",
            attrs  => [$attributeName]
        };

        my $result = $this->ldapSearch($args);
        if ( $result->is_error() ) {
            $this->{errors}->addError(
                'ERROR_WHILE_SEARCHING',
                [
"getLastUidnumberFromLDAP: Search for $attributeName failed",
                    $result->error()
                ]
            );
            return undef;
        }
        my @list = $result->entries();
        $ret =
          ( $_->get_value($attributeName) > $ret )
          ? $_->get_value($attributeName)
          : $ret
          foreach (@list);
    }
    return $ret if $ret > 0;
    return -1;
}

sub getSchema {
    my $this = shift;
    return $this->{schema};
}

sub getObjectClasses {
    my $this = shift;
    return $this->{objectClasses};
}

sub getObjectClassLookup {
    my $this = shift;
    return $this->{objectClassLookup};
}

sub getObjectClassLookupLC {
    my $this = shift;
    return $this->{objectClassLookupLC};
}

sub getAttributes {
    my $this = shift;
    return $this->{attributes};
}

sub getAttributeLookup {
    my $this = shift;
    return $this->{attributeLookup};
}

sub getAttributeLookupLC {
    my $this = shift;
    return $this->{attributeLookupLC};
}

sub getUserBase {
    my $this = shift;
    return $this->{userBase};
}

#=pod
#writeEntryToLdif ( $Net::Ldap::Entry, $workarea ) -> 1
#
#Writes the entry to $workarea/bla.ldif
#
#=cut

sub writeEntryToLdif {
    my $entry    = shift;
    my $workArea = shift;
    my $fileName = $workArea . '/debug.ldif';
    return 0 unless ( $entry && $fileName );
    my $ldif = Net::LDAP::LDIF->new( $fileName, "w", onerror => 'undef' );
    $ldif->write_entry($entry);

    return 1;
}

=pod
---++ ObjectMethod getUserDN ( $loginAttributeName, $login ) -> $list

Example: If your users log in via uid you pass uid=someuser and the function returns a list of entries found in the userbase
matching the filer = "uid=someuser"

=cut

sub getUserDN {
    my $this               = shift;
    my $loginAttributeName = shift;
    my $value              = shift;
    my $userBase           = $this->{userBase} if defined( $this->{userBase} );

    Foswiki::Func::writeDebug($loginAttributeName);
    Foswiki::Func::writeDebug($value);
    Foswiki::Func::writeDebug($_) foreach (@$userBase);
    unless ( scalar @$userBase && $loginAttributeName && $value ) {
        $this->{errors}->addError( 'MISSING_PARAMETERS',
            ['getUserDN: parameters are missing or userbase not set'] );
        return [];
    }

    my $list = [];

    foreach my $base (@$userBase) {
        my $args = {
            base   => $base,
            scope  => 'sub',
            filter => "$loginAttributeName=$value",
            attrs  => ['1.1']
        };

        my $result = $this->ldapSearch($args);
        if ( $result->is_error() ) {
            $this->{errors}->addError(
                'ERROR_WHILE_SEARCHING',
                [
                    "getUserDN: Search for $loginAttributeName=$value failed",
                    $result->error()
                ]
            );
            return [];
        }
        my @entries = $result->entries();
        push @$list, $_->dn() foreach (@entries);
    }
    return $list;
}

#=pod
#
#=cut

sub _mergeArrays {
    my $array1 = shift;
    my $array2 = shift;
    my $result = [ sort keys %{ { map { $_ => 1 } @$array1, @$array2 } } ];
    return $result;
}

=pod

=cut

sub trimSpaces {
    my $s = shift;
    return if !$s;
    $s =~ s/^[[:space:]]+//s;    # trim at start
    $s =~ s/[[:space:]]+$//s;    # trim at end
    return $s;
}

=pod
---++ ObjectMethod hasError ( )

see Foswiki::Plugins::LdapGuiPlugin::Error->hasError()

=cut

sub hasError {
    my $this = shift;
    return ( $this->{errors}->hasError() );
}

1;
