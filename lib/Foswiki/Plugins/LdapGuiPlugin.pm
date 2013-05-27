package Foswiki::Plugins::LdapGuiPlugin;

use strict;
use warnings;

use Net::LDAP qw(LDAP_REFERRAL);
use Net::LDAP::Extension::SetPassword;
use Net::LDAP::Entry;
use Net::LDAP::LDIF;
use Foswiki::Plugins::LdapGuiPlugin::RequestData;
use Foswiki::Plugins::LdapGuiPlugin::LdapUtil;
use Foswiki::Plugins::LdapGuiPlugin::Error;

our $VERSION           = '0.1';
our $RELEASE           = '0.1';
our $SHORTDESCRIPTION  = 'Plugin interface for LDAP GUI over Foswiki';
our $NO_PREFS_IN_TOPIC = 1;
our $pluginName        = 'LdapGuiPlugin';

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;
    Foswiki::Func::registerRESTHandler( 'modifyData', \&_modifyData );
    Foswiki::Func::registerTagHandler( 'JSONREGEXP', \&_jsonRegexp );
    Foswiki::Func::registerTagHandler( 'LDAPGETATTRIBUTE',
        \&_ldapGetAttribute );
    return 1;

}

=pod

_modifyData

RESTHandler called when LDAP entries are going to get modified by the user form

=cut

sub _modifyData {
    my ( $session, $subject, $verb, $response ) = @_;

    my $query = $session->{request};
    my $web   = $session->{webName};
    my $topic = $session->{topicName};

    #foreach my $n ( keys $query->{param} ) {
    #    foreach ( @{ $query->{param}->{$n} } ) {
    #        Foswiki::Func::writeDebug("$n :      $_ ");
    #    }
    #}

    #Foswiki::Func::writeDebug( "GCUID: " . Foswiki::Func::getCanonicalUserID );

    my $loginSchema = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiLoginSchema};
    my $formLoginName = $loginSchema->{add}->{loginName};
    my $formLoginPW   = $loginSchema->{add}->{loginPWD};
    my $loginAttributeName =
      $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiLoginAttribute};

    my $error = Foswiki::Plugins::LdapGuiPlugin::Error->new();
    my $option = Foswiki::Plugins::LdapGuiPlugin::Option->new( $query, $error );

    my $ldapUtil = Foswiki::Plugins::LdapGuiPlugin::LdapUtil->new($error);
    if ( $ldapUtil->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return "FAIL FOR LDAPUTIL\n\n";
    }

    my $requestData =
      Foswiki::Plugins::LdapGuiPlugin::RequestData->new( $query, $option,
        $ldapUtil->getSchema, $error,
        [ 'name', $Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute} ] )
      ;    #name clashes with FormPlugin
    if ( $requestData->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return "FAIL FOR REQUESTDATA\n\n";
    }

    my $password  = $requestData->getOtherByName($formLoginPW);
    my $loginAttr = $requestData->getAttributeByName($loginAttributeName);

    my $userBase = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBase};
    my $user     = @{$loginAttr}[0];
    my $args     = {
        base   => @{$userBase}[0],
        scope  => 'sub',
        filter => "$loginAttributeName=$user"
    };
    $error->writeErrorsToDebug();
    my $result = $ldapUtil->ldapSearch($args);
    Foswiki::Func::writeDebug( "SC:  " . $result->count() );
    my $entry;

    if ( $result->count() == 1 ) {
        $entry = $result->pop_entry();
    }
    else {
        $error->addError(
            'MORE_THAN_ONE_USER',
            [
"The user $user is defined multiple times in the user base. Can not find out which one to modify"
            ]
        );
    }

    unless ( defined $entry ) {
        $error->writeErrorsToDebug();
        my $url = Foswiki::Func::getScriptUrl(
            $web, $topic, 'oops',
            template => "oopssaveerr",
            param1   => "Sorry $user but I failed before modify"
        );
        Foswiki::Func::redirectCgiQuery( undef, $url );
        return 0;
    }

    $error->writeErrorsToDebug();
    my $bindDN = $entry->dn();
    $error->writeErrorsToDebug();

    my $modifyHash =
      $ldapUtil->getModifyReplaceHash( $entry, $requestData->getAttributes() );
    $error->writeErrorsToDebug();
    Foswiki::Func::writeDebug( "$_  :" . $modifyHash->{$_} )
      foreach ( keys %$modifyHash );

    if ( $error->hasError ) {
        $error->writeErrorsToDebug();

        #TODO: use own template
        my $url = Foswiki::Func::getScriptUrl(
            $web, $topic, 'oops',
            template => "oopssaveerr",
            param1   => "Sorry $user but I failed before modify"
        );
        Foswiki::Func::redirectCgiQuery( undef, $url );
        return 0;
    }
    if (
        $ldapUtil->ldapModifyReplace(
            $entry->dn(), $password, $entry->dn(), $modifyHash
        )
      )
    {

        #Foswiki::Func::writeDebug("IT WORKED");
    }
    else {
        $error->writeErrorsToDebug();
        my $url = Foswiki::Func::getScriptUrl(
            $web, $topic, 'oops',
            template => "oopssaveerr",
            param1   => "Sorry $user but I failed on modify"
        );
        Foswiki::Func::redirectCgiQuery( undef, $url );
        return 0;
    }

    my $url = Foswiki::Func::getScriptUrl(
        $web, $topic, 'oops',
        template => "oopssaveerr",
        param1   => "Successfully modified your data $user :-)"
    );
    Foswiki::Func::redirectCgiQuery( undef, $url );
    return 1;
}

sub _ldapGetAttribute {
    my ( $session, $params, $theTopic, $theWeb ) = @_;
    my $userID;

    #need the loginattribute value
    if (
        $Foswiki::cfg{UserMappingManager} eq 'Foswiki::Users::LdapUserMapping' )
    {
        $userID = Foswiki::Func::getCanonicalUserID();
    }
    else {
        return '';
    }

    unless ( defined $userID or defined $params->{attribute} ) {
        return '';
    }

    my $attrName = $params->{attribute};

    my $error    = Foswiki::Plugins::LdapGuiPlugin::Error->new();
    my $ldapUtil = Foswiki::Plugins::LdapGuiPlugin::LdapUtil->new($error);
    if ( $ldapUtil->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return "FAIL AT LDAPUTIL\n\n";
    }
    my $userBase  = $ldapUtil->{userBase};
    my $loginAttr = $ldapUtil->{loginAttribute};
    foreach (@$userBase) {
        my $arg = {
            base   => $_,
            scope  => 'sub',
            filter => "$loginAttr=$userID"
        };
        my $search = $ldapUtil->ldapSearch($arg);
        if ( $search->count == 1 ) {
            my $entry = $search->pop_entry();
            if ( $entry->exists($attrName) ) {
                return $entry->get_value($attrName);
            }
        }
        elsif ( $search->count > 1 ) {
            return '';
        }

    }

    return '';
}

=pod

_jsonRegexp 
...because escaping is unpleasant inside JSON strings

=cut

sub _jsonRegexp {
    my ( $session, $params, $theTopic, $theWeb ) = @_;
    my $regexp = $params->{regexp};
    if ($regexp) {
        $regexp =~ s/"/\\"/g;
        $regexp =~ s/\\/\\\\/g;
    }
    return "\\\"$regexp\\\"";
}

1;
