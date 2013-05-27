#---+ Extensions
#---++ LdapGuiPlugin
# **STRING**
# IP address (or hostname) of the LDAP server
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiServerHost} = '127.0.0.1';

# **NUMBER**
# Ldap protocol version to use when querying the server; 
# Possible values are: 2, 3
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiServerVersion} = '3';

# **NUMBER**
# Port used when binding to the LDAP server
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiPort} = 389;

# **STRING**
# Base DN to use in searches
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBaseDN} = 'dc=my,dc=domain,dc=com';

# **BOOLEAN**
# Allow Proxy Bind: If allowed the Plugin tries to bind against the specifies proxy account.
# default is unchecked
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiAllowProxyBind} = 0;

# **PERL**
# A list of trees where to search for users records.
# One subtree MUST be specified as an option or the plugin
# will reject the request, so at least one user base subtree must be defined.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBase} = ['ou=people,dc=my,dc=domain,dc=com'];

# **BOOLEAN**
# Allow aliases for LdapGuiUserBase. If activated the options for generating a form will accept these aliases
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiAllowUserBaseAliases} = 0;

# **STRING**
# The user mail attribute. This is the attribute name used to fetch
# users e-mail.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiLoginAttribute} = 'uid';

# **STRING**
# The user mail attribute. This is the attribute name used to fetch
# users e-mail.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiMailAttribute} = 'mail';

# **STRING**
# The user's wiki name attribute. This is the attribute to generate
# the WikiName from. 
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiWikiNameAttributes} = 'cn';

# **PERL**
# A list of trees where to search for group records. This MUST be specified
# to check if chosen groups (for example for adding a user to that group) are defined 
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGroupBase} = ['ou=group,dc=my,dc=domain,dc=com'];

# **BOOLEAN**
# Allow aliases for LdapGuiGroupBase. If activated the options for generating a form will accept these aliases
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiAllowGroupBaseAliases} = 0;

# **STRING 50**
# Prevent certain names from being looked up in LDAP
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiExclude} = 'WikiGuest, ProjectContributor, RegistrationAgent, UnknownUser, AdminGroup, NobodyGroup, AdminUser, admin, guest';

# **PERL**
# A list of attributes which get checked for duplicates before inserting or modifying data
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiNoDuplicateAttributes} = ['uid', 'uidNumber'];

# **PERL**
# A hash which contains options for the %LDAPGUILOGIN{ type='' }% Macro
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiLoginSchema} = {
   'add' => {
      'loginName' => 'LdapLoginAttributeName',
      'loginPWD' => 'LdapLoginPasswordAttributeName'
      },
   'modify' => {
      'loginName' => 'uid',
      'loginPWD' => 'LdapLoginPasswordAttributeName'
      }
};

# **BOOLEAN**
# Allow LdapGuiGlue: if unchecked, the option 'LDAPGLUE' gets ignored
# default is unchecked
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGlueAllow} = 0;

# **PERL**
# LdapGuiGlue configuration: basically this is a hash containing a rule how specific attribute values are constructed.
# Defaults to a rule of how cn can be 'glued' together from LdapFirstName and LdapLastName
# Attention: if you allow this function, for example 'cn' gets ignored and the plugin searches for the rule parameters. If they are not found
# this is going to throw an error message
# The keys of the rulehash are the attributes to search for, the values act as a delimiter. If no delimiter should be used it should be undef
# Example for default: 'cn' := 'LdapFirstName' ++ ' ' ++ 'LdapLastName' 
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGlue} = {
   'cn' => {
      'attributes' => [
          'LdapFirstName',
          'sn'
          ],
   'delimiter'  => ' '
      }
};

# **BOOLEAN**
# Allow LdapGuiAllowProxyUser: if checked, the option 'LDAPADDTOGROUP' adds a user to the chosen groups through a proxy user who has write access to these groups
# if unchecked the user who submits the form data must have write access to groups
# default is unchecked
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiAllowProxyUser} = 0;

# **STRING**
# The DN to use when binding to the LDAP server; if undefined anonymous binding
# will be used. Example 'cn=proxyuser,dc=my,dc=domain,dc=com'
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBindDN} = '';

# **PASSWORD**
# The password used when binding to the LDAP server
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiBindPassword} = 'secret';

# **PERL**
# LdapGuiGroupIdentifier: Alias name which identifies the subtree to a group. This is only needed if LDAPADDTOGROUP was specified through an option.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGroupIdentifier} = { 
    'users' => 'ou=group,dc=my,dc=domain,dc=com'
};

# **PERL**
# LdapGuiGroupIdentifier: Alias name which identifies the subtree to a group. This is only needed if LDAPADDTOGROUP was specified through an option.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiGroupIDIdentifier} = { 
    '100' => 'cn=groupname,ou=group,dc=my,dc=domain,dc=com'
};

# **PERL**
# LdapGuiUserBaseAliases: Alias name which identifies the subtrees for users to add.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUserBaseAliases} = { 
    'people' => 'ou=people,dc=my,dc=domain,dc=com'
};

# **STRING**
# The attribute that should be used to collect group members. This is the name of the
# attribute in a group record used to point to the user record. For example, in a possix setting this
# is the uid of the relevant posixAccount. If groups are implemented using the object class
# 'groupOfNames' the MemberAttribute will store a literal DN pointing to the account record. In this
# case you have to switch on the MemberIndirection flag below.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{MemberAttribute} = 'memberUid';

# **STRING**
# The attribute that identifies a group. Defaults to gidNumber
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{GroupAttribute} = 'gidNumber';

# **STRING**
# Uid counter. Set an initialization value.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUidCount} = '1000';

# **BOOLEAN**
# Choose if you want to set the uidNumbers automatically.
# default is unchecked
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiAutosetUidNumber} = 1;

# **PERL**
# LdapGuiPasswordAttributes: LDAP attributes indicating user passwords.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiPasswordAttribute} = ['userPassword'];

# **STRING**
# Set this to the charset encoding of data coming from the LDAP server.
# Normally this should be 'utf-8', but might differ in some cases.
# Data read from the server will then be converted from this encoding
# and translated to your site's charset encoding as configured in <code>{Site}{CharSet}</code>.
# WARNING: if you change the charset encoding after having used a different one for some time
# you will require to remove all cached data in <code>.../working/work_areas/LdapContrib</code>
# and <code>.../working/work_areas/LdapNgPlugin/cache</code>. Otherwise this data 
# will be reused assuming a false charset encoding.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiCharSet} = 'utf-8';

# **BOOLEAN**
# Use SASL authentication when binding to the server; Note, when using SASL the 
# BindDN and BindPassword setting are used to configure the SASL access.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUseSASL} = 0;

# **STRING**
# List of SASL authentication mechanism to try; defaults to 'PLAIN CRAM-MD5
# EXTERNAL ANONYMOUS'
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiSASLMechanism} = 'PLAIN CRAM-MD5 EXTERNAL ANONYMOUS';

# **BOOLEAN**
# Use Transort Layer Security (TLS) to encrypt the connection to the LDAP server.
# You will need to specify the servers CA File using the TLSCAFile option
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiUseTLS} = 0;

# **STRING**
# This defines the version of the SSL/TLS protocol to use. Possible values are:
# 'sslv2', 'sslv3',  'sslv2/3' or 'tlsv1'
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSSSLVersion} = 'tlsv1';

# **STRING**
# Specify how to verify the servers certificate. Possible values are: 'require', 'optional'
# or 'require'.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSVerify} = 'require';

# **STRING**
# Pathname of the directory containing CA certificates
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSCAPath} = '';

# **STRING**
# Filename containing the certificate of the CA which signed the server?EUR(TM)s certificate.
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSCAFile} = '';

# **STRING**
# Client side certificate file
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSClientCert} = '';

# **STRING**
# Client side private key file
$Foswiki::cfg{Plugins}{LdapGuiPlugin}{LdapGuiTLSClientKey} = '';

1;
