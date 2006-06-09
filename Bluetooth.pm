package Net::Bluetooth;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Carp;
require Exporter;
require DynaLoader;
require 5.007;

@ISA = qw(Exporter DynaLoader);
@EXPORT = qw(get_remote_devices sdp_search register_service unregister_service);
$VERSION = '0.32';
bootstrap Net::Bluetooth $VERSION;

sub newsocket {
my $class = shift;
my $proto = shift;
my $client = shift;
my $addr = shift;
my $self = {};

	return if($proto !~ /^RFCOMM$|^L2CAP$/i);

        $self->{PROTO} = $proto;

	#### test this
	if(defined($client) && defined($addr)) {
		$self->{SOCK_FD} = $client;
		$self->{ADDR} = $addr;
	}

	else {
		my $sock = _socket($proto);
		return if($sock < 0);
		$self->{SOCK_FD} = $sock;
	}

        bless($self, $class);
        return $self;
}
                                                                                                                      

sub connect {
my $self = shift;
my $addr = shift;
my $port = shift;

	return if(_connect($self->{SOCK_FD}, $addr, $port, $self->{PROTO}) < 0);

	$self->{ADDR} = $addr;
	$self->{PORT} = $port;

	return 0;
}


sub _debug {
my $self = shift;
	print "addr: $self->{ADDR}\n";
	print "sock: $self->{SOCK_FD}\n";
	print "proto: $self->{PROTO}\n";
}


sub bind {
my $self = shift;
my $port = shift;

	return if(_bind($self->{SOCK_FD}, $port, $self->{PROTO}) < 0);
	$self->{PORT} = $port;

	return 0;
}


sub listen {
my $self = shift;
my $backlog = shift;

	return if(_listen($self->{SOCK_FD}, $backlog) < 0);

	return 0;
}


sub accept {
my $self = shift;

	my ($client, $addr) = _accept($self->{SOCK_FD}, $self->{PROTO});
	return undef if($client < 0);

	return(Net::Bluetooth->newsocket($self->{PROTO}, $client, $addr));
}


sub close {
my $self = shift;

	_close($self->{SOCK_FD});
	$self->{SOCK_FD} = -1;
}


sub getpeername {
my $self = shift;

	my ($addr, $port) = _getpeername($self->{SOCK_FD}, $self->{PROTO});

	return($addr, $port);
}


sub perlfh {
my $self = shift;

	*SOCK = _perlfh($self->{SOCK_FD});
	return \*SOCK;
}


sub fileno {
my $self = shift;

	return($self->{SOCK_FD});
}


1;
__END__

=head1 NAME

Net::Bluetooth - Perl Bluetooth Interface

=head1 SYNOPSIS


  use Net::Bluetooth;

  #### list all remote devices in the area
  my $device_ref = get_remote_devices();
  foreach $addr (keys %$device_ref) {
	print "Address: $addr Name: $device_ref->{$addr}\n";
  }


  #### search for a specific service on a remote device
  my @sdp_array = sdp_search($addr, 0x1101, "");

  #### foreach service record
  foreach $rec_ref (@sdp_array) {
	#### Print all available information for service
	foreach $key (keys %$rec_ref) {
		print "Key: $key Value: $rec_ref->{$key}\n";
	}
  }


  #### Create a RFCOMM client 
  $obj = Net::Bluetooth->newsocket("RFCOMM");
  if($obj->connect($addr, $port) != 0) {
	print "connect error: $!\n";
	exit;
  }

  #### create a Perl filehandle for reading and writing
  *SERVER = $obj->perlfh();
  $amount = read(SERVER, $buf, 256);
  close(SERVER);


  #### register and unregister a service
  my $sdp_session = register_service("RFCOMM", 1, 0x1101, "GPS");
  if(!$sdp_session) {
	#### couldn't register service
  }
  unregister_service($sdp_session);


  #### create a RFCOMM server
  $obj = Net::Bluetooth->newsocket("RFCOMM");
  #### bind to port 1
  if($obj->bind(1) != 0) {
	print "bind error: $!\n";
	exit;
  }

  #### listen with a backlog of 2
  if($obj->listen(2) != 0) {
	print "listen error: $!\n";
	exit;
  }

  #### accept a client connection
  $new_obj = $obj->accept();
  if(!defined($new_obj)) {
	print "client accept failed: $!\n";
	exit;
  }

  #### get client information
  my ($caddr, $port) = $new_obj->getpeername();

  #### create a Perl filehandle for reading and writing
  *CLIENT = $new_obj->perlfh();
  print CLIENT "stuff";
  close(CLIENT);
  $obj->close();





=head1 DESCRIPTION

This module creates a Bluetooth interface for Perl.

Currently it only works with the Bluez libs, which can be 
obtained at www.bluez.org. Please make sure BlueZ is installed
and working properly before you try to use this module.
Depending on your system BlueZ maybe already installed or
you may have to build it yourself, and do some configuration.

You can verify BlueZ can detect devices and services with
the utilities that come with it (hciconfig, sdptool, hcitool, etc).

In the near future the interface will change to add several
more calls as well as Windows support.

=head1 FUNCTIONS

get_remote_devices()
    Searches for remote Bluetooth devices. The search will
    take approximately 10 seconds (This will be a configurable 
    value in the future.). When finished, it will return a hash
    reference that contains the device address and name. The
    address is the key and the name is the value.

sdp_search($addr, $uuid, $name)
sdp_search($addr, $uuid, "")
sdp_search($addr, 0, $name)
sdp_search($addr, 0, "")
    This searches a specific device for service records. The first
    argument is the device address which is not optional. The uuid
    argument can be a valid uuid or 0. The name argument can be a
    valid service name or "". It will return services that match
    the uuid or service name if supplied, otherwise it will return
    all public service records for the device.

    The return value is a list which contains a hash reference for
    each service record found. The key/values for the hash are as follows:
    SERVICE_NAME: Service Name
    SERVICE_DESC: Service Description
    SERVICE_PROV: Service Provider
    RFCOMM: RFCOMM Port
    L2CAP: L2CAP Port
    UNKNOWN: Unknown Protocol  Port
    If any of the values are unavailable, the keys will not exist.

    If $addr is "local" the call will use the local SDP server.


register_service("RFCOMM", 1, 0x1101, "GPS")
    This call registers a service with the local SDP server. The
    first argument is the protocol type which can either be "RFCOMM"
    or "L2CAP". The second argument is the port number. The third
    argument is the service uuid. The fourth argument is the service
    name.

    The return value is a handle to the service you have registered,
    which can be passed to unregister_service to unregister the service.
    The value will be 0 if there is a failure.

    If you also plan to create a server for this service, remember to 
    make sure you create a socket of the same type and bind to the same
    port.
    
unregister_service($service_handle)
   This unregisters your service with the local SDP server. The service 
   will be unregistered without this call when the application exits.
                                                                                                                     

=head1 OBJECTS

Currently this module provides a bluetooth socket object. This object
is used to create bluetooth sockets and interface with them. There
are two types of sockets supported, RFCOMM and L2CAP. The methods
are listed below.

newsocket("RFCOMM")
    This constructs a socket object for a RFCOMM socket or L2CAP
    socket.

connect($addr, $port)
    This calls the connect() system call with address and port you
    supply. You can use this to connect to a server. Returns 0 on
    success.

bind($port)
    This calls the bind() system call with the port you provide. 
    You can use this to bind to a port if you are creating a server.
    Returns 0 on success.

    As a side note, RFCOMM ports can only range from 1 - 30.

listen($backlog)
    This calls the listen() system call with the backlog you provide.
    Returns 0 on success.

accept()
    This calls the accept() system call and creates a new bluetooth
    socket object which is returned. On failure it will return undef.

perlfh()
    This call returns a Perl filehandle for a open socket. You can
    use the Perl filehandle as you would any other filehandle, except
    with Perl calls that use the socket address structure. This 
    provides a easy way to do socket IO instead of doing it through the
    socket object. Currently this is the only way to do socket IO,
    although soon I will provide read/write calls through the object
    interface.

close()
    This closes the socket object. This can also be done through the
    Perl close() call on a created Perl filehandle.

getpeername()
    This returns the address and name for a open bluetooth socket.


=head1 REQUIREMENTS
You need BlueZ installed and working.

=head1 AUTHOR

Ian Guthrie
IGuthrie@aol.com

Copyright (c) 2006 Ian Guthrie. All rights reserved.
               This program is free software; you can redistribute it and/or
               modify it under the same terms as Perl itself.

=head1 SEE ALSO

www.bluez.org
http://people.csail.mit.edu/albert/bluez-intro/index.html
O'Reilly's Linux Unwired

perl(1).

=cut
