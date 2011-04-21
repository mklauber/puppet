require 'puppet/application'

class Puppet::Application::Cert < Puppet::Application

  should_parse_config
  run_mode :master

  attr_accessor :all, :ca, :digest, :signed

  def subcommand
    @subcommand
  end
  def subcommand=(name)
    # Handle the nasty, legacy mapping of "clean" to "destroy".
    sub = name.to_sym
    @subcommand = (sub == :clean ? :destroy : sub)
  end

  option("--clean", "-c") do
    self.subcommand = "destroy"
  end

  option("--all", "-a") do
    @all = true
  end

  option("--digest DIGEST") do |arg|
    @digest = arg
  end

  option("--signed", "-s") do
    @signed = true
  end

  option("--debug", "-d") do |arg|
    Puppet::Util::Log.level = :debug
  end

  require 'puppet/ssl/certificate_authority/interface'
  Puppet::SSL::CertificateAuthority::Interface::INTERFACE_METHODS.reject {|m| m == :destroy }.each do |method|
    option("--#{method}", "-#{method.to_s[0,1]}") do
      self.subcommand = method
    end
  end

  option("--verbose", "-v") do
    Puppet::Util::Log.level = :info
  end

  def help
    <<-HELP

puppet-cert(8) -- Manage certificates and requests
========

SYNOPSIS
--------
Standalone certificate authority. Capable of generating certificates,
but mostly used for signing certificate requests from puppet clients.


USAGE
-----
puppet cert <action> [-h|--help] [-V|--version] [-d|--debug] [-v|--verbose]
  [--digest <digest>] [<host>]


DESCRIPTION
-----------
Because the puppet master service defaults to not signing client
certificate requests, this script is available for signing outstanding
requests. It can be used to list outstanding requests and then either
sign them individually or sign all of them.

ACTIONS
-------

Every action except 'list' and 'generate' requires a hostname to act on,
unless the '--all' option is set.

* clean:
  Revoke a host's certificate (if applicable) and remove all files
  related to that host from puppet cert's storage. This is useful when
  rebuilding hosts, since new certificate signing requests will only be
  honored if puppet cert does not have a copy of a signed certificate
  for that host. If '--all' is specified then all host certificates,
  both signed and unsigned, will be removed.

* fingerprint:
  Print the DIGEST (defaults to md5) fingerprint of a host's
  certificate.

* generate:
  Generate a certificate for a named client. A certificate/keypair will
  be generated for each client named on the command line.

* list:
  List outstanding certificate requests. If '--all' is specified, signed
  certificates are also listed, prefixed by '+', and revoked or invalid
  certificates are prefixed by '-' (the verification outcome is printed
  in parenthesis).

* print:
  Print the full-text version of a host's certificate.

* revoke:
  Revoke the certificate of a client. The certificate can be specified
  either by its serial number (given as a decimal number or a
  hexadecimal number prefixed by '0x') or by its hostname. The
  certificate is revoked by adding it to the Certificate Revocation List
  given by the 'cacrl' configuration option. Note that the puppet master
  needs to be restarted after revoking certificates.

* sign:
  Sign an outstanding certificate request.

* verify:
  Verify the named certificate against the local CA certificate.


OPTIONS
-------
Note that any configuration parameter that's valid in the configuration
file is also a valid long argument. For example, 'ssldir' is a valid
configuration parameter, so you can specify '--ssldir <directory>' as an
argument.

See the configuration file documentation at
http://docs.puppetlabs.com/references/stable/configuration.html for the
full list of acceptable parameters. A commented list of all
configuration options can also be generated by running puppet cert with
'--genconfig'.

* --all:
  Operate on all items. Currently only makes sense with the 'sign',
  'clean', 'list', and 'fingerprint' actions.

* --digest:
  Set the digest for fingerprinting (defaults to md5). Valid values
  depends on your openssl and openssl ruby extension version, but should
  contain at least md5, sha1, md2, sha256.

* --debug:
  Enable full debugging.

* --help:
  Print this help message

* --verbose:
  Enable verbosity.

* --version:
  Print the puppet version number and exit.


EXAMPLE
-------
    $ puppet cert list
    culain.madstop.com
    $ puppet cert sign culain.madstop.com


AUTHOR
------
Luke Kanies


COPYRIGHT
---------
Copyright (c) 2011 Puppet Labs, LLC Licensed under the Apache 2.0 License

    HELP
  end

  def main
    if @all
      hosts = :all
    elsif @signed
      hosts = :signed
    else
      hosts = command_line.args.collect { |h| h.downcase }
    end
    begin
      @ca.apply(:revoke, :to => hosts) if subcommand == :destroy
      @ca.apply(subcommand, :to => hosts, :digest => @digest)
    rescue => detail
      puts detail.backtrace if Puppet[:trace]
      puts detail.to_s
      exit(24)
    end
  end

  def setup
    require 'puppet/ssl/certificate_authority'
    exit(Puppet.settings.print_configs ? 0 : 1) if Puppet.settings.print_configs?

    Puppet::Util::Log.newdestination :console

    if [:generate, :destroy].include? subcommand
      Puppet::SSL::Host.ca_location = :local
    else
      Puppet::SSL::Host.ca_location = :only
    end

    begin
      @ca = Puppet::SSL::CertificateAuthority.new
    rescue => detail
      puts detail.backtrace if Puppet[:trace]
      puts detail.to_s
      exit(23)
    end
  end

  def parse_options
    # handle the bareword subcommand pattern.
    result = super
    unless self.subcommand then
      if sub = self.command_line.args.shift then
        self.subcommand = sub
      else
        help
      end
    end
    result
  end
end
