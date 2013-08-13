package Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::Glue;

use strict;
use warnings;

use Foswiki::Plugins::LdapGuiPlugin::Error;
use Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::RootNode;
use Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::Node;
use Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::StringNode;

sub new {
    my $class       = shift;
    my $rules       = shift;
    my $chosenRules = shift;
    my $query       = shift;
    my $errObject   = shift;

    return undef unless ( $rules && $query );

    $errObject = Foswiki::Plugins::LdapGuiPlugin::Error->new if not $errObject;

    my $this = {
        rules           => $rules,
        chosen          => $chosenRules,
        query           => $query,
        rootList        => [],
        treeList        => [],
        nameAssoc       => {},
        formatFunctions => {
            lowercase => sub { my $s = shift; return lc $s; },
            uppercase => sub { my $s = shift; return uc $s; }
        },
        errors => $errObject
    };
    bless $this, $class;
    return $this;

}

=pod

=cut

#TODO actually it is useless to distinguish between NODE, STRINGNODE and ROOTNODE... 1 class and a less specific constructor would do the job
sub parseRules {
    my $this        = shift;
    my $rules       = $this->{rules};
    my $chosenRules = $this->{chosen};
    my $query       = $this->{query};

    my %ruleKeys =
      map { lc($_) => $_ } ( keys %{$rules} );   # to get case sensitivity fails

    foreach my $subject (@$chosenRules) {

        if ( not exists $rules->{$subject} ) {
            if ( not exists $ruleKeys{$subject} ) {
                $this->{errors}
                  ->addError( 'NO_GLUE_RULE', ["No such rule $subject."] );
            }
            else {
                $subject = $ruleKeys{ $subject }
                  ; #LDAP attribute names are case insensitive, glue rule-attribute names too.
            }
        }

        my $delimiter = $rules->{$subject}->{delimiter} || '';
        my $asString =
          ( exists $rules->{$subject}->{asString} )
          ? $rules->{$subject}->{asString}
          : [];
        my $glueAttributes =
          ( exists $rules->{$subject}->{attributes} )
          ? $rules->{$subject}->{attributes}
          : [];
        my $formatFunctionsUser =
          ( exists $rules->{$subject}->{formatFunctions} )
          ? $rules->{$subject}->{formatFunctions}
          : [];
        my $format = $this->getFormatFunctionList($formatFunctionsUser);

        my $count  = 0;
        my $maxlen = -1;

        if (@$glueAttributes) {
            $maxlen = scalar @$glueAttributes - 1;
        }
        else {
            $this->{errors}->addError( 'UNDEFINED_ATTRIBUTES_FOR_SUBJECT',
                ["No attribute rules where found for $subject rule."] );
        }

        if ( exists $rules->{$subject}->{asString} )
        {    #if the bitmask exists, we use it
            $asString = $rules->{$subject}->{asString};
        }

        my $childNodes = [];
        my $node       = undef;
        foreach my $attr (@$glueAttributes) {
            my $piece = '';
            if ( not scalar @$asString ) {

#every attribute parameter is treaded as a form parameter and is searched in the request
                if ( exists $query->{param}->{$attr} ) {
                    $piece =
                      Foswiki::Plugins::LdapGuiPlugin::LdapUtil::trimSpaces(
                        $query->{param}->{$attr}[0] );
                    $node =
                      Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::Node->new(
                        $attr, '', [], $this->{errors} );
                    $node->setValue(
                        Foswiki::Plugins::LdapGuiPlugin::LdapUtil::trimSpaces(
                            $query->{param}->{$attr}[0]
                        )
                    );
                }
                else {

                    #placeholder for rootnode, later substituted
                    $node =
                      Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::Node->new(
                        $attr, '', [], $this->{errors} );
                }
            }
            else {
                if ( scalar @$asString != scalar @$glueAttributes ) {
                    $this->{errors}->addError(
                        'INDEX_MISSMATCH',
                        [
"Configuration of asString and attributes in rule for $subject specifies different count of elements. Must be equal."
                        ]
                    );
                }

                $this->{errors}->addError( 'INDEX_OUT_OF_BOUNDS',
                    ["There is no element $count in rule $subject."] )
                  if ( $count > $maxlen );

                if ( ${$asString}[$count] ) {

                    #this attribute should get treated as a string
                    $node =
                      Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::StringNode
                      ->new( $attr, '', [], $this->{errors} );
                    $node->setValue($attr);
                }
                else {

                    #not treaded as a string -> search for request attribute
                    if ( exists $query->{param}->{$attr} ) {
                        $piece =
                          Foswiki::Plugins::LdapGuiPlugin::LdapUtil::trimSpaces(
                            $query->{param}->{$attr}[0] );
                        $node =
                          Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::Node
                          ->new( $attr, '', [], $this->{errors} );
                        $node->setValue(
                            Foswiki::Plugins::LdapGuiPlugin::LdapUtil::trimSpaces(
                                $query->{param}->{$attr}[0]
                            )
                        );

                   #Foswiki::Func::writeDebug("AS PARAM: $attr, $node->{name}");
                    }
                    else {

                        #placeholder for rootnode, later substituted
                        $node =
                          Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::Node
                          ->new( $attr, '', [], $this->{errors} );
                    }
                }
            }

            $count++;

            if ( defined $node ) {

                #$node->printdebug();
                push @{$childNodes}, $node;
            }
            else {
                $this->{errors}->addError(
                    'NO_GLUE_PARAMETER',
                    [
"Attribute $attr, for glue rule $subject, was not found or empty."
                    ]
                );
            }

        }
        ##debug childnodes
        my $rootNode =
          Foswiki::Plugins::LdapGuiPlugin::LdapGuiGlue::RootNode->new( $subject,
            $childNodes, $delimiter, $format, $this->{errors} );

        push @{ $this->{rootList} }, $subject;
        push @{ $this->{treeList} }, $rootNode;
        $this->{nameAssoc}->{$subject} = $rootNode;

        #Foswiki::Func::writeDebug("ROOTNODE: ".$rootNode->{name});

        #$this->debugWriteOut;
    }
    if ( $this->{errors}->hasError ) {
        return 0;
    }
    return 1;

}

=pod

=cut

sub getFormatFunctionList {
    my $this       = shift;
    my $userChoice = shift;
    return [] unless $userChoice;
    return [] unless scalar @$userChoice;
    my $formatList = [];
    foreach (@$userChoice) {
        if ( exists $this->{formatFunctions}->{ lc $_ } ) {
            push @$formatList, $this->{formatFunctions}->{ lc $_ };
        }
        else {
            return [];    #fail
        }
    }
    return $formatList;
}

=pod

=cut

sub test {
    my $this = shift;
    my $h    = shift;
    foreach ( keys $h ) {
        Foswiki::Func::writeDebug("HELL $_");
        foreach my $a ( @{ $h->{$_} } ) {
            Foswiki::Func::writeDebug("YEAH $a->{name}");
        }
    }
}

=pod

=cut

sub glueTogether {
    my $this  = shift;
    my $trees = $this->{treeList};
    foreach (@$trees) {
        $this->glue($_);
    }
    return 1;
}

=pod

=cut

sub glue {
    my $this = shift;
    my $me   = shift;

    if ( $me->{type} eq "string" ) {
        return $me->applyFormat() . $me->{delimiter};
    }
    if ( $me->{type} eq "node" ) {
        return $me->applyFormat() . $me->{delimiter};
    }
    if ( $me->{type} eq "root" ) {
        my $val       = $me->getValue();
        my $delimiter = $me->{delimiters};
        unless ($val) {
            foreach ( @{ $me->getChildren() } ) {
                $me->appendValue( $this->glue($_) . $delimiter );
            }

#TODO:     return $me->getValue;   #<- this would be enough if delimiters and so on were bound to the nodes directly.
            $me->applyFormat();
            $val = $me->getValue();
        }
        $val =~ s/[[:space:]]+/ /g;
        $val = Foswiki::Plugins::LdapGuiPlugin::LdapUtil::trimSpaces($val)
          if $val;
        $val =~ s/$delimiter+$// if $delimiter;
        $val =~ s/^$delimiter+// if $delimiter;
        $me->setValue($val);
        return $val;
    }
}

=pod

=cut

sub substitutePseudoRootNodes {
    my $this     = shift;
    my $rootList = $this->{rootList};
    my $treeList = $this->{treeList};
    my $assoc    = $this->{nameAssoc};

    foreach my $root (@$treeList) {
        my $rootChildren = $root->getChildren;
        my $childNumber  = 0;
        foreach my $child (@$rootChildren) {
            if ( exists $assoc->{ $child->{name} } ) {
                $root->{children}->[$childNumber] = $assoc->{ $child->{name} };
            }
            $childNumber++;
        }
    }

    return 1;

}

=pod

=cut

sub isNotCylic {
    my $this  = shift;
    my $trees = $this->{treeList};
    Foswiki::Func::writeDebug($_) foreach (@$trees);
    foreach (@$trees) {
        unless ( $this->acyclicRoot( $_, [] ) ) {
            $this->{errors}->addError(
                'CYCLIC_RULES',
                [
"Glue rule definition results in cyclic behavior - aborting glue process"
                ]
            );
            return 0;
        }
    }
    return 1;
}

=pod

=cut

sub acyclicRoot {
    my $this    = shift;
    my $root    = shift;
    my $visited = shift;
    push @$visited, $root->{name};
    my $childNodes  = $root->getChildren;
    my $isNotCyclic = 1;
    foreach my $child (@$childNodes) {
        if ( $child->{type} eq 'root' ) {
            foreach my $v (@$visited) {
                if ( $v eq $child->{name} ) {
                    $this->{errors}->addError(
                        'CYCLIC_RULE_ROOT',
                        [
"Rule $root->{name} leads to cyclic substitution for root node $v ."
                        ]
                    );
                    $isNotCyclic = 0;
                    return $isNotCyclic;
                }
            }
            $isNotCyclic = $this->acyclicRoot( $child, $visited );
        }
    }
    return $isNotCyclic;
}

=pod

=cut

sub debugWriteOut {
    my $this = shift;
    my $rl   = $this->{rootList};
    my $tl   = $this->{treeList};
    my $na   = $this->{nameAssoc};

    Foswiki::Func::writeDebug();

    Foswiki::Func::writeDebug('<ROOTLIST>');
    Foswiki::Func::writeDebug($_) foreach (@$rl);
    Foswiki::Func::writeDebug('</ROOTLIST>');

    Foswiki::Func::writeDebug('<TREELIST>');
    foreach my $t (@$tl) {
        Foswiki::Func::writeDebug( 'ROOT: ' . $t->{name} );
        $t->printdebug;
        my $c = $t->getChildren();

        Foswiki::Func::writeDebug('CHILDREN: ');
        foreach my $p (@$c) {
            $p->printdebug;
        }
    }
    Foswiki::Func::writeDebug('</TREELIST>');

}

1;
