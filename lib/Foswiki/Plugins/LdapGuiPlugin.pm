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
    Foswiki::Func::registerRESTHandler( 'addData',    \&_addData );

    Foswiki::Func::registerTagHandler( 'JSONREGEXP',  \&_jsonRegexp );
    Foswiki::Func::registerTagHandler( 'CREATELOGIN', \&_createLogin );
    Foswiki::Func::registerTagHandler( 'LDAPGETATTRIBUTE',
        \&_ldapGetAttribute );

#Foswiki::Func::writeDebug($Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute});
#Foswiki::Func::writeDebug($Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUidCount});
    my $workArea = Foswiki::Func::getWorkArea($pluginName);
    my $fileName = $workArea . '/uidCounter.txt';
    my $uidfh;
    if ( not open( $uidfh, "<", $fileName ) ) {
        open( $uidfh, ">", $fileName );

#Foswiki::Func::writeDebug($Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUidCount});
        if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUidCount} >= 0 ) {
            print $uidfh $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUidCount};
            print $uidfh "\n";
        }
        else {

            #fail
            die;
        }
        close $uidfh;
    }
    else {
        close $uidfh;
    }

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

    Foswiki::Func::writeDebug( "GCUID: " . Foswiki::Func::getCanonicalUserID );

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
        return "FAIL AT LDAPUTIL\n\n";
    }

    my $requestData =
      Foswiki::Plugins::LdapGuiPlugin::RequestData->new( $query, $option,
        $ldapUtil->getSchema, $error,
        [ 'name', $Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute} ] )
      ;    #name clashes with FormPlugin
    if ( $requestData->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return "FAIL AT REQUESTDATA\n\n";
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
        Foswiki::Func::writeDebug("IT WORKED");
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

=pod
_moveEntry

REST call to move an entry from one location inside the DIT to another

TODO: To be implemented
=cut

sub _moveEntry {
    my ( $session, $subject, $verb, $response ) = @_;
    my $query = $session->{request};
    my $web   = $query->{param}->{web}[0];
    my $topic = $query->{param}->{topic}[0];

    return 0;
}

=pod
_addData
REST call to add data to the LDAP server

TODO: Test this proper this is just an experimental version

=cut

sub _addData {
    my ( $session, $subject, $verb, $response ) = @_;
    my $query = $session->{request};
    my $web   = $query->{param}->{web}[0];
    my $topic = $query->{param}->{topic}[0];

    #debug $query output
    #foreach my $n ( keys $query->{param} ) {
    #    foreach ( @{ $query->{param}->{$n} } ) {
    #        Foswiki::Func::writeDebug("$n :      $_ ");
    #    }
    #}
    my $error = Foswiki::Plugins::LdapGuiPlugin::Error->new();
    my $option = Foswiki::Plugins::LdapGuiPlugin::Option->new( $query, $error );

    if ( $option->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        my $page = $error->errorRenderHTML( $web, $topic );
        return $page;
    }

    my $ldapUtil = Foswiki::Plugins::LdapGuiPlugin::LdapUtil->new($error);
    if ( $ldapUtil->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        my $page = $error->errorRenderHTML( $web, $topic );
        return $page;
    }

    my $requestData =
      Foswiki::Plugins::LdapGuiPlugin::RequestData->new( $query, $option,
        $ldapUtil->getSchema, $error,
        [ 'name', $Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute} ] )
      ; #TODO: dont add 'name' automatically, this is for form plugin compatibility
    if ( $requestData->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        my $page = $error->errorRenderHTML( $web, $topic );
        return $page;
    }

    #autogenerate NumberAttributes (test specific uidNumber)
    my $uidNumber;
    if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiAutosetUidNumber} ) {
        $uidNumber = $requestData->getAttributeByName('uidNumber')->[0]
          if $requestData->hasAttribute('uidNumber');
        if ( defined $uidNumber ) {
            if ( $ldapUtil->isUniqueLdapAttribute( 'uidNumber', $uidNumber ) ) {
                if ( $ldapUtil->hasError() || $error->hasError() ) {
                    $error->writeErrorsToDebug();

                    #return '1';
                    my $page = $error->errorRenderHTML( $web, $topic );
                    return $page;
                }
            }
            else {
                $uidNumber = undef;
            }
        }
        unless ( defined $uidNumber ) {
            my $uidNumber = _getLastUidnumberFromFile();
            if ( $uidNumber > 0 ) {
                if ( 0
                    && $ldapUtil->isUniqueLdapAttribute( 'uidNumber',
                        $uidNumber ) )
                {
                    if ( $ldapUtil->hasError() || $error->hasError() ) {
                        $error->writeErrorsToDebug();

                        #return '2';
                        my $page = $error->errorRenderHTML( $web, $topic );
                        return $page;
                    }
                    else {
                        $requestData->addAttribute( 'uidNumber', [$uidNumber] );
                    }
                }
                else {
                    $uidNumber =
                      $ldapUtil->getLastUidnumberFromLDAP('uidNumber');
                    if ( $ldapUtil->hasError() || $error->hasError() ) {
                        $error->writeErrorsToDebug();

                        #return '3';
                        my $page = $error->errorRenderHTML( $web, $topic );
                        return $page;
                    }
                    if ( $uidNumber < 0 ) {
                        return "too small -> fail!";
                    }
                    else {
                        $requestData->addAttribute( 'uidNumber',
                            [ $uidNumber + 1 ] );
                        unless ( _updateLastUidNumber( $uidNumber + 2 ) ) {
                            my $page = $error->errorRenderHTML( $web, $topic );
                            return $page;
                        }
                    }
                }
            }
        }
    }

    #create entry
    my $attributes = $requestData->getAttributes();
    my $subTree;
    my $objectClasses;
    my $loginAttributeName =
      $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiLoginAttribute};

    if ( defined $attributes ) {

        #get sub tree
        if ( $option->hasSubtrees ) {
            $subTree =
              $option->getSubtrees()->[0];    #limit it to 1 subtree for testing
            my $loginAttributeValue =
              $requestData->getLoginAttribute($loginAttributeName);
            if (    defined $loginAttributeName
                and defined $loginAttributeValue
                and not $error->hasError() )
            {
                $subTree =
                    $loginAttributeName . '='
                  . $loginAttributeValue . ','
                  . $subTree;
            }
            else {
                $error->writeErrorsToDebug();

                #return '4';
                my $page = $error->errorRenderHTML( $web, $topic );
                return $page;
            }
            Foswiki::Func::writeDebug(
                "LOGINATTRNAME + USERBASE DN:   $subTree");

            if ( defined $subTree and $subTree ) {

                $objectClasses = $requestData->getObjectClasses();
                unless ( defined $objectClasses ) {
                    $error->writeErrorsToDebug();
                    my $page = $error->errorRenderHTML( $web, $topic );
                    return $page;
                }
            }
        }
        else {

            #return '5';
            my $page = $error->errorRenderHTML( $web, $topic );
            return $page;
        }
    }
    else {

        #return '6';
        my $page = $error->errorRenderHTML( $web, $topic );
        return $page;
    }
    my $entry = _createNewEntry( $attributes, $subTree, $objectClasses );

    #validate entry

    unless ( _isValidEntry( $ldapUtil->getSchema(), $objectClasses, $entry ) ) {
        $error->writeErrorsToDebug();

        #return '7';
        my $page = $error->errorRenderHTML( $web, $topic );
        return $page;
    }

    #    _writeLDIF($entry);    #just for debugging

    #get user
    my $loginSchema = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiLoginSchema};
    my $formLoginName = $loginSchema->{add}->{loginName};
    my $formLoginPW   = $loginSchema->{add}->{loginPWD};

    my $user     = $requestData->getOtherByName($formLoginName);
    my $password = $requestData->getOtherByName($formLoginPW);

    my $bindDNs = $ldapUtil->getUserDN( $loginAttributeName, $user );
    $error->writeErrorsToDebug();
    my $bindDN;

    if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiAllowProxyBind} )
    {    #this is like opening the door for everyone.. dont do this
        $bindDN   = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBindDN};
        $password = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBindPassword};
    }
    else {
        if ( scalar @$bindDNs == 0 ) {
            $error->addError(
                'NO_USER_FOUND',
                [
                    "Sorry, but $user could not be found.",
                    'Check the correct spelling of your LDAP login name.'
                ]
            );

            #return '8';
            my $page = $error->errorRenderHTML( $web, $topic );
            return $page;
        }
        else {
            if ( scalar @$bindDNs > 1 ) {

                #return '9';
                my $page = $error->errorRenderHTML( $web, $topic );
                return $page;
            }
            else {
                $bindDN = @{$bindDNs}[0];
            }
        }

        unless ( $bindDN && $password && $entry ) {

            #return '10';
            my $page = $error->errorRenderHTML( $web, $topic );
            return $page;
        }
    }

    if ( $ldapUtil->ldapAdd( $bindDN, $password, $entry ) ) {
        if ( $error->hasError ) {
            $error->writeErrorsToDebug();
            my $page = $error->errorRenderHTML( $web, $topic );
            return $page;
        }

    }
    else {
        $error->writeErrorsToDebug();
        my $page = $error->errorRenderHTML( $web, $topic );
        return $page;
    }

    #groups to add the user to? this is the options 'hardcoded' part

    if ( $option->hasGroupsToAdd() ) {
        my $groupDN = $option->getGroupDN();
        Foswiki::Func::writeDebug("GROUPS TO ADD: $_") foreach (@$groupDN);
        if ( scalar @$groupDN ) {
            my $grMemberAttrName =
              $Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute};
            my $member = $entry->get_value($loginAttributeName);
            if ( $grMemberAttrName && $member ) {
                my $addHash = { $grMemberAttrName => $member };

                if ( $Foswiki::{cfg}{Plugins}{LdapGuiPlugin}
                    {LdapGuiAllowProxyUser} )
                {    #should be another proxy user
                    $bindDN =
                      $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBindDN};
                    $password =
                      $Foswiki::cfg{Plugins}{LdapGuiPlugin}
                      {LdapGuiBindPassword};
                }

                unless (
                    $ldapUtil->ldapAddToGroup(
                        $bindDN, $password, $groupDN, $addHash
                    )
                  )
                {
                    my $page = $error->errorRenderHTML( $web, $topic );
                    return $page;
                }
            }
            else {
                my $page = $error->errorRenderHTML( $web, $topic );
                return $page;
            }
        }
        else {

        }
    }

    #membergroups out of the request

    if ( $requestData->hasMemberGroups() ) {
        my $groups =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGroupIDIdentifier};
        my $memberGroups = $requestData->getMemberGroups();
        Foswiki::Func::writeDebug("$_") foreach (@$memberGroups);
        my $groupDN = [];
        foreach my $chosen (@$memberGroups) {
            if ( exists $groups->{$chosen} and defined $groups->{$chosen} ) {
                push @$groupDN, $groups->{$chosen};
            }
            else {
                Foswiki::Func::writeDebug();
            }
        }
        if ( scalar @$groupDN ) {
            my $grMemberAttrName =
              $Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute};
            my $member = $entry->get_value($loginAttributeName);
            if ( $grMemberAttrName && $member ) {
                my $addHash = { $grMemberAttrName => $member };

                if ( $Foswiki::{cfg}{Plugins}{LdapGuiPlugin}
                    {LdapGuiAllowProxyUser} )
                {    #should be another proxy user
                    $bindDN =
                      $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBindDN};
                    $password =
                      $Foswiki::cfg{Plugins}{LdapGuiPlugin}
                      {LdapGuiBindPassword};
                }

                unless (
                    $ldapUtil->ldapAddToGroup(
                        $bindDN, $password, $groupDN, $addHash
                    )
                  )
                {
                    my $page = $error->errorRenderHTML( $web, $topic );
                    return $page;
                }
            }
            else {
                my $page = $error->errorRenderHTML( $web, $topic );
                return $page;
            }
        }
        else {

        }

    }
    else {

        #Foswiki::Func::writeDebug("NO GROUPS TO ADD USER");
    }
    $error->writeErrorsToDebug();

#	if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}{AllowLdapTriggers} ) {
#		if ( $option->hasTriggers ) {
#			my $target = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapTriggerTargetUrl} . $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapTriggerTargetPort};
#			my $triggers = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{Triggers};
#			my $triggerUserIds = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{TriggerIds};
#			my $triggerName;
#			if ( exists $triggers->{$option->getTrigger} and defined $triggers->{$option->getTrigger} ) {
#				$triggerName = triggers->{$option->getTrigger};
#
#			}
#			my $content = $requestData->getContent;
#           $content = $content . '&' . "ldaptriggername=$triggerName";
#			if ( _trigger ( $target, $content, $triggerName, $error ) ) {
#	        } else {
#				$error->writeErrorsToDebug();
#	        	my $page = $error->errorRenderHTML($web,$topic);
#	        	return $page;
#	        }
#		}
#    }

    #TODO: {cfg}Foswiki structure
    #TODO: write to a file in working/LdapGuiPlugin/uid.ltc as marker
    #TODO: build option for triggers
    #	my $content = $requestData->getContent;
    #    if ( defined $content ) {
    #		if ( _trigger ( '', $content, 'dunno', $error ) ) {
    #			return "success";
    #        } else {
    #			$error->writeErrorsToDebug();
    #        	my $page = $error->errorRenderHTML($web,$topic);
    #        	return $page;
    #        }
    #    }
    #TODO replace it, this is no error :)
    my $url = Foswiki::Func::getScriptUrl(
        $web, $topic, 'oops',
        template => "oopssaveerr",
        param1   => 'User Added. :-)'
    );
    Foswiki::Func::redirectCgiQuery( undef, $url );

    return 1;
}

=pod
TODO use it later
=cut

sub _getLoginData {
    my $loginSchema = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiLoginSchema};
    my $formLoginName = '';
    my $formLoginPW   = '';
    if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiAllowProxyBind} ) {
        $formLoginName = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBindDN};
        $formLoginPW =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBindPassword};
    }
    else {
        $formLoginName = $loginSchema->{add}->{loginName};
        $formLoginPW   = $loginSchema->{add}->{loginPWD};
    }
    return ( $formLoginName, $formLoginPW );

}

=pod
_isValidEntry

look if the entry we created matches required attributes of its objectclasses

TODO: Rewrite this function so that it uses LdapUtil
=cut

sub _isValidEntry {
    my $schema        = shift;
    my $objectClasses = shift;
    my $entry         = shift;

    my $must       = [];
    my $may        = [];
    my @attributes = $entry->attributes();

    foreach my $oc (@$objectClasses) {

        my $tmpMust = [];
        my $tmpMay  = [];

        foreach ( $schema->must($oc) ) {
            push @$tmpMust, lc $_->{name};
        }

        $must = _mergeArrays( $must, $tmpMust );

        foreach ( $schema->may($oc) ) {
            push @$tmpMay, lc $_->{name};
        }
        $may = _mergeArrays( $may, $tmpMay );
    }

    my %lookupMust = map { lc $_ => 1 } @$must;
    my %lookupMay  = map { lc $_ => 1 } @$may;
    my %lookupAttr = map { lc $_ => 1 } @attributes;

    #check if all must attributes are contained
    foreach (@$must) {
        Foswiki::Func::writeDebug("FAILED FOR $_ in @$must")
          if not exists $lookupAttr{$_};
        return 0 unless ( exists $lookupAttr{$_} );

    }

    # check if all our attributes are contained in must or may sets
    foreach ( $entry->attributes() ) {
        Foswiki::Func::writeDebug("FAILED FOR $_ in @attributes")
          if not( exists $lookupMust{ lc $_ } || exists $lookupMay{ lc $_ } );
        return 0
          unless ( exists $lookupMust{ lc $_ } || exists $lookupMay{ lc $_ } );
    }
    return 1;
}

=pod
_mergeArrays (@1,@2) -> @(1++2)
=cut

sub _mergeArrays {
    my $array1 = shift;
    my $array2 = shift;
    my $result = [ sort keys %{ { map { $_ => 1 } @$array1, @$array2 } } ];
    return $result;
}

=pod
 _createNewEntry ($attributes, $dn, $objectClasses) -> $entry

Takes the attributes parsed by RequestData, a dn and objectClasses and creates a new entry object.

=cut

sub _createNewEntry {
    my ( $data, $dn, $objectClass ) = @_;
    my $entry = Net::LDAP::Entry->new;

    $entry->dn($dn);
    foreach (@$objectClass) {
        $entry->add( 'objectClass' => $_ );
    }

    foreach my $key ( keys $data ) {
        my $arraySize = scalar @{ $data->{$key} };
        if ( not $arraySize ) {
            $entry->add( $key => '_none_' );
        }
        else {
            if ( $arraySize == 1 ) {
                $entry->add( $key => $data->{$key}->[0] )
                  ;    #one value -> no array ref
            }
            else {
                $entry->add( $key => $data->{$key} );    #else array ref
            }

        }

    }

    return $entry;
}

=pod
_writeLDIF

For debug purposes or a messy kind of logger function. If this gets used as a logger the password attributes should get removed or ignored before writing the ldif to the file system.

=cut

sub _writeLDIF {
    my $entry = shift;

    my $workArea = Foswiki::Func::getWorkArea($pluginName);
    my $fileName = $workArea . '/testtest.ldif';

    my $ldif = Net::LDAP::LDIF->new( $fileName, "w", onerror => 'undef' );
    $ldif->write_entry($entry);
    return $ldif;
}

=pod
TODO: not yet used

Check if the unique attributes are actually unique and a new entry is not a duplicate in one of the subtrees.

=cut

sub _entryHasDuplicateAttr {
    my $entry = shift;
    my $ldap  = shift;
    die "_entryHasDuplicateAttr: No entry or ldap object given"
      unless ( $entry && $ldap );
    my $trees = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBase};
    my $checkForDuplicates =
      $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiNoDuplicateAttributes};
    return 1 if not scalar @$checkForDuplicates;
    return 1 if not scalar @$trees;
    my $filter = '(|';

    foreach (@$checkForDuplicates) {
        $_ =~ s/^\s+//;
        $_ =~ s/\s+$//;
        $filter .= '(';
        $filter .= "$_=" . $entry->get_value($_);
        $filter .= ')';
    }
    $filter .= ')';

    $ldap->bind();
    foreach my $sb (@$trees) {
        my $result = $ldap->search(
            base   => $_,
            filter => $filter
        );
        return 1 if $result->count;
    }
    return 0;
}

=pod
LDAPerror ( $Net::Ldap::Message ) -> $string 

=cut

sub LDAPerror {
    my $mesg = @_;
    return
        'RETURN_CODE: '
      . $mesg->code
      . ' MESSAGE: '
      . $mesg->error_name . ' :'
      . $mesg->error_text
      . ' MESSAGE_ID: '
      . $mesg->mesg_id . ' DN: '
      . $mesg->dn;

    #	---
    # Programmer note:
    #
    #  "$mesg->error" DOESN'T work!!!
    #
    #print "\tMessage: ", $mesg->error;
    #-----
}

=pod
_isUniqueUidNumber ()
=cut

sub _isUniqueUidNumber {
    my $ldap      = shift;
    my $uidNumber = shift;
    my $userBase  = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBase};
    return 0 unless ( $ldap && scalar @$userBase && $uidNumber );
    foreach (@$userBase) {
        my $search = $ldap->search(
            base   => $_,
            scope  => 'sub',
            filter => "uidNumber=$uidNumber",
            attrs  => ['1.1']
        );

        #Foswiki::Func::writeDebug("COUNT: ".$search->count ( ));
        return 0 if $search->count();
    }
    return 1;
}

#TODO: enhance this function to only find numbers in a specified range!
sub _getLastUidnumberFromLDAP {
    my $ldap     = shift;
    my $userBase = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBase};
    return -1 unless ( $ldap && scalar @$userBase );
    my $ret = -1;
    foreach (@$userBase) {
        my $search = $ldap->search(
            base   => $_,
            scope  => 'sub',
            filter => 'uidNumber=*',
            attrs  => ['uidNumber']
        );
        my @list = $search->entries();
        $ret =
          ( $_->get_value('uidNumber') > $ret )
          ? $_->get_value('uidNumber')
          : $ret
          foreach (@list);
    }
    return $ret if $ret > 0;
    return -1;
}

=pod

=cut

sub _updateLastUidNumber {
    my $newVal = shift;
    return 0 if not defined $newVal;

    my $workArea = Foswiki::Func::getWorkArea($pluginName);
    my $fileName = $workArea . '/uidCounter.txt';
    use Fcntl qw(:DEFAULT :flock);
    my $fh;
    open( $fh, ">", $fileName );
    flock( $fh, LOCK_SH ) or die "can't lock: $!";
    seek( $fh, 0, 0 );
    print $fh ($newVal);
    print $fh "\n";
    close $fh;
    return 1;
}

=pod

=cut

sub _getLastUidnumberFromFile {
    my $workArea = Foswiki::Func::getWorkArea($pluginName);
    my $fileName = $workArea . '/uidCounter.txt';
    my $count    = -1;
    use Fcntl qw(:DEFAULT :flock);
    my $fh;
    open( $fh, "+<", $fileName ) or return $count;
    flock( $fh, LOCK_SH ) or die "can't lock: $!";
    $count = <$fh>;
    $count =~ s/\n//;
    seek( $fh, 0, 0 );
    print $fh ( $count + 1 );
    print $fh "\n";
    close $fh;
    return $count;
}

=pod

=cut

sub _ldapGetAttribute {
    my ( $session, $params, $theTopic, $theWeb ) = @_;
    my $userID;

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

=pod

=cut

sub _trigger {
    my $target   = shift;
    my $data     = shift;
    my $workflow = shift;
    my $error    = shift;
    use CGI;
    use Encode;
    use HTTP::Request;
    use HTTP::Request::Common qw(POST);
    use HTTP::Response;
    use LWP;
    use LWP::UserAgent;
    Foswiki::Func::writeDebug("TARGET: $target , WORKFLOW: $workflow");
    my $ua = LWP::UserAgent->new;
    my $response =
      $ua->post( $target, Content => encode( "iso-8859-1", $data ) );

    unless ( $response->code eq '200' ) {

        #TODO: get some information out of response body
        $error->addError( 'TRIGGER_REQUEST_FAILED',
            [ 'Could not trigger.', "response code: " . $response->code ] );
        return 0;
    }
    return 1;
}

1;
