package Foswiki::Plugins::LdapGuiPlugin;

use strict;
use warnings;

use URI::Escape;
use CGI;
use Foswiki::Plugins::LdapGuiPlugin::RequestData;
use Foswiki::Plugins::LdapGuiPlugin::LdapUtil;
use Foswiki::Plugins::LdapGuiPlugin::Error;
use Foswiki::Plugins::LdapGuiPlugin::Renderer;

our $VERSION           = '0.1';
our $RELEASE           = '0.1';
our $SHORTDESCRIPTION  = 'Plugin interface for LDAP GUI over Foswiki';
our $NO_PREFS_IN_TOPIC = 1;
our $pluginName        = 'LdapGuiPlugin';

=pod
 authenticate=>1, validate=>1, http_allow=>'POST'
=cut

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;
    Foswiki::Func::registerRESTHandler( 'modifyData', \&_modifyData );
    Foswiki::Func::registerRESTHandler( 'addData',    \&_addData );

    Foswiki::Func::registerTagHandler( 'JSONREGEXP', \&_jsonRegexp );
    Foswiki::Func::registerTagHandler( 'LDAPGETATTRIBUTE',
        \&_ldapGetAttribute );
    Foswiki::Func::registerTagHandler( 'LDAPGUITESTMODE', \&_ldapGuiTestMode );

    if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiAutosetUidNumber} ) {
        my $toSet = $Foswiki::cfg{Plugins}{LdapGuiPlugin}
          {LdapGuiAutosetNumericalAttributes};
        my $workArea = Foswiki::Func::getWorkArea($pluginName);
        foreach ( keys %{$toSet} ) {
            my $fileName = $workArea . '/' . $_ . '.txt';
            $fileName =~ /(.*)/;
            $fileName = $1;
            my $fh;
            my $min = $toSet->{$_}->{min};
            my $max = $toSet->{$_}->{max};
            unless ( ( $min =~ m/^\d+$/ ) && ( $max =~ m/^\d+$/ ) ) {
                die
                  "minimum or maximum for number attribute $_ is not a number";
            }
            if ( not open( $fh, "<", $fileName ) ) {
                if ( open( $fh, ">", $fileName ) ) {
                    if ( $min > 0 and $max > 0 ) {
                        if ( $max <= $min ) {
                            warn
"maximum smaller or equal minimum for number attribute $_";
                            print $fh $max;
                        }
                        print $fh $min;
                        print $fh "\n";
                    }
                    else {
                        #fail
                        die "minimum or maximum negative";
                    }
                    close $fh;
                }
                else {
                    die "can not create file";
                }
            }
            else {
                close $fh;
            }
        }
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

    my $error = Foswiki::Plugins::LdapGuiPlugin::Error->new();

    unless ( _isTrustedWeb( $web, $error ) ) {
        return $error->errorRenderHTML( $web, $topic );
    }

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

    my $option = Foswiki::Plugins::LdapGuiPlugin::Option->new( $query, $error );

    my $ldapUtil = Foswiki::Plugins::LdapGuiPlugin::LdapUtil->new($error);
    if ( $ldapUtil->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    my $requestData = Foswiki::Plugins::LdapGuiPlugin::RequestData->new(
        $query, $option,
        $ldapUtil->getSchema,
        $error,
        [
            'name', $Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute},
            $loginAttributeName
        ]
    );    #TODO name clashes with FormPlugin -> for now its hardcoded ignored
    if ( $requestData->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    my $password  = ${ $requestData->getOtherByName($formLoginPW) }[0];
    my $loginAttr = $requestData->getOtherByName($loginAttributeName);

    my $userBase = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBase};
    my $user     = @{$loginAttr}[0];

    my $targetDN = undef;
    if ( $requestData->hasDN() ) {
        $targetDN = $requestData->getOtherByName('dn');
    }

    my $args = {
        base   => @{$userBase}[0],
        scope  => 'sub',
        filter => "$loginAttributeName=$user"
    };
    my $bindEntry;
    my $targetEntry;

    my $result = $ldapUtil->ldapSearch($args);

    #Foswiki::Func::writeDebug( "SC:  " . $result->count() );
    if ( $result->count() == 1 ) {
        $bindEntry = $result->pop_entry();
    }
    else {
        my $entries = [ $result->entries() ];
        my $msg     = [
"The user $user was not found, or defined multiple times in the user base. Can not find out which one to bind to",
            "matched DN:"
        ];
        foreach (@$entries) {
            push @$msg, $_->dn();
        }
        $error->addError( 'NO_OR_MORE_THAN_ONE_MATCH', $msg );
    }
    if ( defined $targetDN and @{$targetDN} == 1 and ( $$targetDN[0] ne '' ) ) {

        #Foswiki::Func::writeDebug($targetDN);
        $args = {
            base   => @{$targetDN}[0],
            scope  => 'base',
            filter => "(objectclass=*)"
        };
        $result = $ldapUtil->ldapSearch($args);

        #Foswiki::Func::writeDebug( "SC:  " . $result->count() );
        if ( $result->count() == 1 ) {
            $targetEntry = $result->pop_entry();
        }
        else {
            my $entries = [ $result->entries() ];
            my $msg     = [
                "The DN "
                  . @{$targetDN}[0]
                  . " was not found, or matched multiple times",
                "matched DN:"
            ];
            foreach (@$entries) {
                push @$msg, $_->dn();
            }
            $error->addError( 'NO_OR_MORE_THAN_ONE_MATCH', $msg );
        }
    }
    else {
        $targetEntry = $bindEntry;
    }

    unless ( defined $bindEntry and defined $targetEntry ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    my $bindDN = $bindEntry->dn();

    if ( $error->hasError ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    my $modifyHash =
      $ldapUtil->getModifyHash( $targetEntry, $requestData->getAttributes(),
        $option->getModifyOptions );
    $error->writeErrorsToDebug();

#Foswiki::Func::writeDebug( "$_  :" . $modifyHash->{$_} ) foreach ( keys %$modifyHash );

    if ( $error->hasError ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }
    if (
        $ldapUtil->ldapModify(
            $bindEntry->dn(), $password, $targetEntry->dn(), $modifyHash
        )
      )
    {

        #Foswiki::Func::writeDebug("IT WORKED");
    }
    else {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }
    if (   $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTestMode}
        or $error->hasError )
    {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    my $renderer = Foswiki::Plugins::LdapGuiPlugin::Renderer->new();
    $renderer->title('Modify Successful');
    $renderer->headl2('Modify Successful');
    $renderer->headl3('Modifications:');
    $renderer->modification($modifyHash);
    $renderer->break(2);
    $renderer->linkback( $web, $topic );
    return $renderer->writePage();
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


TODO: If we can add Users, we should add users to groups too, see if LDAPmodify could so this
TODO: Generalize, so that the handler actually just has to call a more abstract subroutine

=cut

sub _addData {
    my ( $session, $subject, $verb, $response ) = @_;
    my $query = $session->{request};
    my $web   = $session->{webName};
    my $topic = $session->{topicName};

    #debug $query output
    #foreach my $n ( keys $query->{param} ) {
    #    foreach ( @{ $query->{param}->{$n} } ) {
    #        Foswiki::Func::writeDebug("$n :      $_ ");
    #    }
    #}
    my $error = Foswiki::Plugins::LdapGuiPlugin::Error->new();

    unless ( _isTrustedWeb( $web, $error ) ) {
        return $error->errorRenderHTML( $web, $topic );
    }

    my $option = Foswiki::Plugins::LdapGuiPlugin::Option->new( $query, $error );

    if ( $option->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    my $ldapUtil = Foswiki::Plugins::LdapGuiPlugin::LdapUtil->new($error);
    if ( $ldapUtil->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    #autogenerade number attributes

    if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}
        {LdapGuiAllowAutosetNumericalAttributes} )
    {
        my $toSet = $Foswiki::cfg{Plugins}{LdapGuiPlugin}
          {LdapGuiAutosetNumericalAttributes};
        my $workArea = Foswiki::Func::getWorkArea($pluginName);
        use Fcntl qw(:DEFAULT :flock);
        foreach ( keys %{$toSet} ) {
            my $fileName = $workArea . '/' . $_ . '.txt';
            my $number   = -1;
            my $fh;
            my $min  = $toSet->{$_}->{min};
            my $max  = $toSet->{$_}->{max};
            my $step = 1;
            if ( defined $toSet->{$_}->{step} ) {
                if ( $toSet->{$_}->{step} =~ m/^\d+$/ ) {
                    $step = $toSet->{$_}->{step};
                }
            }

            unless ( ( $min =~ m/^\d+$/ ) && ( $max =~ m/^\d+$/ ) ) {
                $error->addError(
                    'NO_NUMBER',
                    [
"minimum or maximum for number attribute $_ is not a number!"
                    ]
                );
                next;
            }
            if ( $min >= $max ) {
                my $tmp = $max;
                $max = $min;
                $min = $max;
            }
            if ( open( $fh, "+<", $fileName ) ) {
                flock( $fh, LOCK_EX ) or die "can't lock: $!";
                $number = <$fh>;
                $number =~ s/\n//;
                Foswiki::Func::writeDebug("We have a number for $_ : $number");
                my $newValue = int($number) + $step;
                if ( $number > 0 ) {
                    if ( $ldapUtil->isUniqueLdapAttribute( $_, $number ) ) {

                        #number is unique
                        #Foswiki::Func::writeDebug("$_ : $number ist unique");
                        if ( $number > $max ) {
                            $error->addError(
                                'MAXIMUM_EXCEEDED',
                                [
                                    "for: $_",
                                    "The maximum of $max was exceeded.",
                                    'Please set a new range in configure.'
                                ]
                            );
                            close $fh or die "Error on closing $fh\n";
                            next;
                        }
                        unless ( $ldapUtil->hasError() || $error->hasError() ) {
                            Foswiki::Func::writeDebug(
"GET $_ OUT_OF_FILE: $fileName   NEWVAL: $newValue"
                            );
                            $query->{param}->{$_} = [$number];
                            seek( $fh, 0, 0 );
                            print $fh "$newValue";
                            print $fh "\n";
                        }
                    }
                    else {
                        #not unique -> search it
                        Foswiki::Func::writeDebug(
                            "$_ : $number ist nicht unique");
                        $number =
                          $ldapUtil->getLastNumberFromLDAP( $_, $min, $max );
                        Foswiki::Func::writeDebug(
                            "$_ : min: $min, max: $max   last number: $number");
                        unless ( $ldapUtil->hasError() || $error->hasError() ) {
                            if ( $number < 0 ) {
                                $error->addError(
                                    'NEGATIVE_AUTOGENERATED_NUMBER',
                                    [
                                        "for: $_",
'No negative value should be found, something went wrong'
                                    ]
                                );
                            }
                            else {
                                $number = $number + 1;    #maybe + step
                                if ( $number > $max ) {
                                    $error->addError(
                                        'MAXIMUM_EXCEEDED',
                                        [
                                            "for: $_",
                                            "The maximum of $max was exceeded.",
'Please set a new range in configure.'
                                        ]
                                    );
                                    close $fh or die "Error on closing $fh\n";
                                    next;
                                }
                                $query->{param}->{$_} = [$number];
                                $newValue = int($number) + $step;
                                seek( $fh, 0, 0 );
                                print $fh "$newValue";
                                print $fh "\n";
                            }
                        }
                    }
                }
                else {
                    $error->addError(
                        'NEGATIVE_AUTOGENERATED_NUMBER',
                        [
                            "for: $_",
'No negative value should be found, something went wrong'
                        ]
                    );
                }
                close $fh or die "Error on closing $fh\n";
            }
            else {
                die "Can not open <+ file $!";
            }
        }
    }

    if ( $ldapUtil->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    my $requestData =
      Foswiki::Plugins::LdapGuiPlugin::RequestData->new( $query, $option,
        $ldapUtil->getSchema, $error,
        [ 'name', $Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute} ] )
      ;    #name clashes with FormPlugin form name
    if ( $requestData->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
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
                return $error->errorRenderHTML( $web, $topic );
            }

            #Foswiki::Func::writeDebug(
            #    "LOGINATTRNAME + USERBASE DN:   $subTree");

            if ( defined $subTree and $subTree ) {

                $objectClasses = $requestData->getObjectClasses();
                unless ( defined $objectClasses ) {
                    $error->writeErrorsToDebug();
                    return $error->errorRenderHTML( $web, $topic );
                }
            }
        }
        else {
            return $error->errorRenderHTML( $web, $topic );
        }
    }
    else {
        return $error->errorRenderHTML( $web, $topic );
    }
    my $entry = _createNewEntry( $attributes, $subTree, $objectClasses );

    #validate entry

    unless ( _isValidEntry( $ldapUtil->getSchema(), $objectClasses, $entry ) ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    _writeLDIF($entry);    #just for debugging

    #get user
    my $loginSchema = $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiLoginSchema};
    my $formLoginName = $loginSchema->{add}->{loginName};
    my $formLoginPW   = $loginSchema->{add}->{loginPWD};

    my $user     = ${ $requestData->getOtherByName($formLoginName) }[0];
    my $password = ${ $requestData->getOtherByName($formLoginPW) }[0];

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
            return $error->errorRenderHTML( $web, $topic );
        }
        else {
            if ( scalar @$bindDNs > 1 ) {
                return $error->errorRenderHTML( $web, $topic );
            }
            else {
                $bindDN = @{$bindDNs}[0];
            }
        }
        unless ( $bindDN && $password && $entry ) {
            return $error->errorRenderHTML( $web, $topic );
        }
    }

    if ( $error->hasError ) {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    if ( $ldapUtil->ldapAdd( $bindDN, $password, $entry ) ) {
        if ( $error->hasError ) {
            $error->writeErrorsToDebug();
            return $error->errorRenderHTML( $web, $topic );
        }
    }
    else {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    #membergroups out of the request

    if ( $requestData->hasMemberGroups() ) {
        my $groups =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGroupIDIdentifier};
        my $memberGroups = $requestData->getMemberGroups();

        #Foswiki::Func::writeDebug("$_") foreach (@$memberGroups);
        my $groupDN = [];
        foreach my $chosen (@$memberGroups) {
            if ( exists $groups->{$chosen} and defined $groups->{$chosen} ) {

                #Foswiki::Func::writeDebug("YESDN: $groups->{$chosen}");
                push @$groupDN, $groups->{$chosen};
            }
            else {

                #Foswiki::Func::writeDebug();
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
                    return $error->errorRenderHTML( $web, $topic );
                }
            }
            else {
                return $error->errorRenderHTML( $web, $topic );
            }
        }
        else {

        }

    }
    else {

        #Foswiki::Func::writeDebug("NO GROUPS TO ADD USER");
    }
    $error->writeErrorsToDebug();    #should tell: NO ERROR
                                     #add group

    #TODO: needs file locks
    #TODO: build option for triggers
    if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUseTrigger} ) {
        my $content = $requestData->getContent;
        my $uniqeName =
          $requestData->getAttributeByName($loginAttributeName)->[0];
        _startTrigger( $content, $uniqeName, $error );
    }
    if (   $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTestMode}
        or $error->hasError )
    {
        $error->writeErrorsToDebug();
        return $error->errorRenderHTML( $web, $topic );
    }

    #happy we are
    my $renderer = Foswiki::Plugins::LdapGuiPlugin::Renderer->new();
    $renderer->title('Add successful');
    $renderer->headl2('Your add request was successfull');
    $renderer->headl3('Entry added:');
    $renderer->entry($entry);
    $renderer->break(2);
    $renderer->linkback( $web, $topic );
    return $renderer->writePage();
}

sub _getLockFile {
    my $fileName = shift;
    my $content  = shift;
    my $error    = shift;
    use Fcntl qw(:DEFAULT :flock);
    my $fh;

    if ( open( $fh, ">", $fileName ) ) {
        if ( flock( $fh, LOCK_EX ) ) {
            print $fh $content;
        }
        else {

            #Foswiki::Func::writeDebug("CANT LOCK $fileName");
            return 0;
        }
    }
    else {
        $error->addError( 'COULD_NOT_CREATE_FILE', ["$fileName"] );
        close $fh;
        return 0;
    }
    close $fh;
    return 1;
}

sub _startTrigger {
    my $content    = shift;
    my $uniqueName = shift;
    my $error      = shift;

    my $workArea = Foswiki::Func::getWorkArea($pluginName);
    my $fileName = $workArea . '/' . $uniqueName;

    if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUseTrigger} ) {
        my $targetURL =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTriggerTargetURL};
        my $tagretPort =
          $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTriggerTargetPort};

        if ( defined $targetURL ) {
            my $target = $targetURL . ':' . $tagretPort;
            if ( defined $content ) {

                if ( defined $workArea and defined $fileName ) {
                    unless ( _getLockFile( $fileName, $content, $error ) ) {
                        return 0;
                    }

                   #atomic file flag in workarea dude
                   #Foswiki::Func::writeDebug( "Trigger File Name: $fileName" );

                    if (
                        _trigger(
                            $target,                 $content,
                            'placeHolderForTrigger', $error
                        )
                      )
                    {
                        return 1;
                    }
                    else {
                        $error->addError( 'ERROR_WHILE_TRIGGER', [] );
                    }
                }
            }
            else {
                $error->addError( 'NO_CONTENT_FOR_TRIGGER', [] );
            }
        }
        else {
            $error->addError( 'NO_TARGET_URL_FOR_TRIGGER', [] );
        }
    }
    unless ( unlink $fileName ) {
        $error->addError( 'COULD_NOT_DELETE', [ "$fileName", "$!" ] );
    }

    return 0;
}

=pod

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

sub _isTrustedWeb {
    my $web   = shift;
    my $error = shift;
    foreach ( @{ $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTrustedWebs} } ) {
        unless ( lc $_ eq lc $web ) {
            $error->addError( 'TRUSTED_WEB_ERROR',
                [ "$web is not trusted.", 'Your request was denied.' ] );
            return 0;
        }
    }
    return 1;
}

=pod
_isValidEntry

look if the entry we created matches required attributes of its objectclasses

TODO: Rewrite this function so that it only uses the LdapUtil object
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

    #Foswiki::Func::writeDebug("OBC   $_") foreach (@$objectClasses);
    my %lookupMust = map { lc $_ => 1 } @$must;

    #Foswiki::Func::writeDebug("MUST   $_") foreach (@$must);
    my %lookupMay = map { lc $_ => 1 } @$may;

    #Foswiki::Func::writeDebug("MAY   $_") foreach (@$may);
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
    my $fileName = $workArea . '/' . $entry->dn . '.ldif';
    $fileName =~ /(.)*/;
    $fileName = $1;
    my $ldif = Net::LDAP::LDIF->new( $fileName, "w", onerror => 'undef' );
    $ldif->write_entry($entry);
    return $ldif;
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
    my $max = $params->{max} || 1;

    my $attrName = $params->{attribute};

    my $error    = Foswiki::Plugins::LdapGuiPlugin::Error->new();
    my $ldapUtil = Foswiki::Plugins::LdapGuiPlugin::LdapUtil->new($error);
    if ( $ldapUtil->hasError() || $error->hasError() ) {
        $error->writeErrorsToDebug();
        return '';
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
                my $values = $entry->get_value( $attrName, asref => 1 );
                my $return = '';
                if ( scalar @$values ) {
                    my $tmp = 0;
                    foreach (@$values) {
                        last if ( $tmp == $max );
                        $return = $return . $_ . ',';
                        $tmp++;
                    }
                    $return =~ s/,$//;
                    return $return;
                }
                else {

                }
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
just a helper function, will get removed

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
LDAP Trigger API
The trigger API could provide a way to trigger events depending on a form action without apache being run as root.
Therefore a stable well defined API is needed which is able to pass needed information to the instance which is triggering the external events.
Example workflow:

	     ----------------
	    | Foswiki Form   |
	     ----------------
	            | RequestData
	            | Options + {trigger option}
	            | web/topic
	     ----------------                                ----------
	    |                |----{RequestData,Options}---->| LDAP     |
	    | LdapGuiPlugin  |                              |          |
	    |   ----------   |<---------Response------------|          |
	     -- TriggerAPI --                                ----------
	    | daemon IP      |
	    | cfg{workflows} |
	    | trigger option |
	    | web/topic      |
	     ----------------
	            |{RequestData+scriptname+userid}             
	            |
	     ---------------
	    |  HttpDaemon   |---{params}--->SCRIPT AS USERID
	    |    (root)     |
	     ---------------

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

sub _ldapGuiTestMode {
    my ( $session, $params, $theTopic, $theWeb ) = @_;
    if ( $Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTestMode} ) {
        return
'LDAPGUIPLUGIN IS CURRENTLY IN TEST MODE - YOU CAN NOT CHANGE YOUR DATA';
    }
    return '';
}

1;
