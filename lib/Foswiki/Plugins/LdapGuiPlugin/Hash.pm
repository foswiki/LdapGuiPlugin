package Foswiki::Plugins::LdapGuiPlugin::Hash;

use strict;
use warnings;

use Digest::SHA;
use Digest::MD5;
use Crypt::PasswdMD5;
use MIME::Base64;
use Foswiki::Plugins::LdapGuiPlugin::Error;

=pod 
---++ClassMethod new()

Creates a new hash object.

usage: 
<verbatim>
my $hasher = Package::Hash->new()
my $hash = $hasher('I am the text', 'ssha');
</verbatim>

$hash will contain the hashed value prepended by {SSHA}. (suitable for LDAP)

Supported algorithms:
   * SHA
   * MD5
   * SSHA
   * SMD5
   * CRYPT

SMELL: As soon as possible this must become more portable, the way random bytes get generated should get changed.

=cut

sub new {
    my $class = shift;
    my $this  = {
        hashAlgorithms => {
            'id' => sub {
                my $text = shift;
                return $text;
            },
            'sha' => sub {
                my $text = shift;
                my $sha  = Digest::SHA->new;
                $sha->add($text);
                my $digest = encode_base64( $sha->digest, '' );
                return '{SHA}' . $digest;
            },
            'md5' => sub {
                my $text = shift;
                my $md5  = Digest::MD5->new;
                $md5->add($text);
                my $digest = encode_base64( $md5->digest, '' );
                return '{MD5}' . $digest;
            },
            'ssha' => sub {
                my $text = shift;
                my $salt = getSalt(4);
                my $ssha = Digest::SHA->new;
                $ssha->add($text);
                $ssha->add($salt);
                my $digest = encode_base64( $ssha->digest . $salt, '' );
                return '{SSHA}' . $digest;
            },
            'smd5' => sub {
                my $text = shift;
                my $salt = getSalt(4);
                my $smd5 = Digest::MD5->new;
                $smd5->add($text);
                $smd5->add($salt);
                my $digest = encode_base64( $smd5->digest . $salt, '' );
                return '{SMD5}' . $digest;
            },
            'crypt' => sub {
                my $text = shift;
                my $salt;
                my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9, qw(. /) );
                $salt = join( "", @chars[ map { rand @chars } ( 1 .. 2 ) ] );
                return '{CRYPT}' . crypt( $text, $salt );
              }
        }
    };
    bless $this, $class;
    return $this;
}

=pod
---++ ObjectMethod getHash ($text, $algorithm) -> $hash

Takes text and the name of the algorithm which should be used and returns the hash prepended with the algorithm name.
returns empty string on failure

=cut

sub getHash {
    my $this = shift;
    my $text = shift;
    my $alg  = shift;
    return '' unless ( $text && $alg );
    if ( exists $this->{hashAlgorithms}->{ lc $alg } ) {
        return $this->{hashAlgorithms}->{ lc $alg }->($text);
    }
    else {

        #die brutally
    }
}

=pod
---++ ObjectMethod addAlgorithm ($algorithmName, \&algorithm) -> $hash

Sets a new algorithm and name to be used.
=cut

sub addAlgorithm {
    my $this      = shift;
    my $name      = shift;
    my $algorithm = shift;
    unless ( $name && $algorithm ) {

        #$this->{error}->addError('',[]);
        return 0;
    }

    return 0 if ( exists $this->{hashAlgorithms}->{ lc $name } );

    $this->{hashAlgorithms}->{ lc $name } = $algorithm;
    return 1;
}

=pod

---++ Private method getSalt ($length) -> $salt

Returns a salt value with the given length of bytes

=cut

sub getSalt {
    my $len = shift;
    my $salt;
    if ( open( my $RAND, '<', "/dev/random/" ) ) {
        read( $RAND, $salt, $len );
        close($RAND);
        return $salt;
    }
    else {
        my @bytes = ();
        for my $i ( 1 .. $len ) {
            push( @bytes, rand(255) );
        }
        $salt = pack( 'C*', @bytes );
    }
    return $salt;
}

1;
