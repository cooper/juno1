#!/usr/bin/perl
#####################################################################
# Server.pm                                                         #
# Created: Tue Sep 15 12:56:51 1998 by jay.kominek@colorado.edu     # 
# Revised: Wed Jun  5 12:59:27 2002 by jay.kominek@colorado.edu     #
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)          #
#                                                                   #
# Consult the file 'LICENSE' for the complete terms under which you #
# may use this file.                                                #
#                                                                   #
#####################################################################
#                   server package - juno ircd                      #
#####################################################################

package Server;
use Utils;
use User;
use Channel;
use strict;
use UNIVERSAL qw(isa);

use Tie::IRCUniqueHash;

my $commands = {'PING'   => \&handle_ping,
		'PONG'   => \&handle_pong,
		# Channel membership
		'JOIN'   => \&handle_join,
		'PART'   => \&handle_part,
		'INVITE' => \&handle_invite,
		'KICK'   => \&handle_kick,
		# Channel status
		'TOPIC'  => \&handle_topic,
		'MODE'   => \&handle_mode,
		# User presence
		'NICK'   => \&handle_nick,
		'KILL'   => \&handle_kill,
		'QUIT'   => \&handle_quit,
		# User status
		'AWAY'   => \&handle_away,
		# Server presence
		'SERVER' => \&handle_server,
		'SQUIT'  => \&handle_squit,
		# Communication
		'PRIVMSG'=> \&handle_privmsg,
		'NOTICE' => \&handle_notice,
		# Burst commands
#		'BU'     => \&handle_burstuser, # these both currently are liable to crash juno :P
#		'BC'     => \&handle_burstchannel
	       };

###################
# CLASS CONSTRUCTOR
###################

# Pass it its name.
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };
  my $connection = shift;

  $this->{'name'}        = $connection->{'servername'};
  $this->{'description'} = $connection->{'description'};
  $this->{'distance'}    = $connection->{'distance'};
  $this->{'proto'}       = $connection->{'proto'};
  $this->{'server'}      = $connection->{'server'};
  $this->{'version'}     = $Utils::VERSION;
  $this->{'last_active'} = time();

  tie my %usertmp,  'Tie::IRCUniqueHash';
  $this->{'users'}    = \%usertmp;
  tie my %childtmp, 'Tie::IRCUniqueHash';
  $this->{'children'} = \%childtmp;

  bless($this, $class);
  if(defined($connection->{'socket'})) {
    $this->{'socket'}    = $connection->{'socket'};
    $this->{'outbuffer'} = $connection->{'outbuffer'};
    $this->setupaslocal($connection->{'initiated'});
  }
  $this->{'server'}->addchildserver($this);
  return $this;
}

sub setupaslocal {
  my $this = shift;
  my $initiated = shift;

  my $server = $this->server;

  # lookup and send password
  if(!$initiated) {
	# when it comes to server linking, passwords mean nothing
	# because the guy who wrote this said so, i assume
	# *adds to todo list*
    $this->senddata("PASS :password\r\n");

  ###################################################################
  # Start dumping the state of the entire network at the new server #

  # Dump the server tree
  # This server has to be sent in the special fashion. All other
  # servers are spewed using the recursive method 'spewchildren'
  $this->senddata(join(' ', # delimiter
		       "SERVER",
		       $server->name,
		       1,
		       0,    # timestamp a
		       time, # timestamp b
		       "Px1",
		       ":".$server->description)."\r\n");
  }
  foreach my $childserver ($server->children()) {
    $this->spewchildren($childserver);
  }

  # Dump the users
  # For big networks, it would be a very good idea to generate all the
  # data that needs to be sent at one time, use Compress::Zlib on that
  # data and then spew it binaryily.

  # As it is, we will merely use the special burst user command
  foreach my $user (values(%{Utils::users()})) {

# I was so excited when i erased BU and BC! :D
    $this->senddata(join(' ',
			"NICK",
			$user->nick,
			$user->server->hops,
			$user->time_create,
			$user->username,
			$user->host,
			$user->server->name,
			"0",
			":".$user->ircname)."\r\n");
	foreach my $channel (values(%{$user->channels()})) {
		$this->senddata(join(' ',
			":".$user->nick,
			"JOIN",
			$channel->{'name'},
			$channel->{'jointime'}->{$user->nick})."\r\n");
	}
			
  }

  # Burst channel modes and topics
  foreach my $channel (values(%{Utils::channels()})) {
    # :server.name BC #channel creationtime modestr modeargs
    # as of June 27th 2010, we burst multiple prefixes as well as channel modes
    # we now burst ~ & and % as well.
	#here we check if each mode is set
	my $cmodes = "";
	my $cargs = "";
	if ($channel->ismode("i")) { $cmodes = $cmodes."i"; }
	if ($channel->ismode("m")) { $cmodes = $cmodes."m"; }
	if ($channel->ismode("n")) { $cmodes = $cmodes."n"; }
	if ($channel->ismode("s")) { $cmodes = $cmodes."s"; }
	if ($channel->ismode("t")) { $cmodes = $cmodes."t"; }
	if ($channel->ismode("k")) {
		$cmodes = $cmodes."k";
		$cargs = $cargs." ".$channel->{key};
	}
	if ($channel->ismode("l")) {
		$cmodes = $cmodes."l";
		$cargs = $cargs." ".$channel->{limit};
	}
	if ($channel->ismode("L")) { # july 7 2010 support for link added 
		$cmodes = $cmodes."L";
		$cargs = $cargs." ".$channel->{link};
	}
	foreach(keys(%{$channel->{'bans'}})) { # june 27 2010 support for bans added 
		$cmodes = $cmodes."b";
		$cargs = $cargs." ".$_;
	}
	foreach(keys(%{$channel->{'mutes'}})) { # july 7 2010 support for mutes added 
		$cmodes = $cmodes."Z";
		$cargs = $cargs." ".$_;
	}
# I was so excited when i erased BU and BC! :D

	$this->senddata(join(' ',
		":".$this->parent->name,
		"MODE",
		$channel->{name},
		"+$cmodes",
		ltrim($cargs))."\r\n");

	if (defined($channel->{topic})) {
	$this->senddata(join(' ',
		":".$this->parent->name,
		"TOPIC",
		$channel->{name},
		$channel->{topicsetter},
		$channel->{topicsettime},
		":".$channel->{topic})."\r\n");
	}

  }
  $this->senddata(join(' ', ":".$server->name." EOS\r\n"));
}

sub spewchildren {
  my $this = shift;
  my $server = shift;
  $this->senddata(join(' ',
		       ":".$this->server->name,
		       "SERVER",
		       $server->name,
		       $server->hops+1,
		       0,    # timestamp a
		       time, # timestamp b
		       "Px1",
		       ":".$server->description)."\r\n");
  foreach($server->children()) {
    $this->spewchildren($_);
  }
}

#####################################################################
# PROTOCOL HANDLERS
###################

##############
# Main Handler
sub handle {
  my $this = shift;
  my $rawline = shift;

  my $line;
  foreach $line (split(/\x00/,$rawline)) {
    $line =~ s/\s+$//;

    $this->{'last_active'} = time();
    delete($this->{'ping_waiting'});

    $line =~ /^\S+ (\S+) .+$/;
    my $command = $1;

    # Parsing stuff from a server is a bit more complicated than parsing
    # for a user.
    if(ref($commands->{$command})) {
      &{$commands->{$command}}($this,$line);
    } else {
      if($line =~ /[\w\d\s]/) {
	Utils::syslog('notice', "Received unknown command string \"$line\" from ".$this->name);
      }
    }
  }
}

# :remote PING :string
sub handle_ping {
  my $this = shift;
  my($from,$command,$arg) = split(/\s+/,shift,3);
  $arg =~ s/^://;
  $this->senddata(":".$this->name." PONG :$arg\r\n");
}

# :remote PONG :string
sub handle_pong {
  # my $this = shift;
  # Don't waste our time doing anything
}

# :remote BU nick username host modestr ircname
sub handle_burstuser {
  my $this = shift;
  my($from,$command,$nick,$username,$host,$modestr,$ircname) =
    split/\s+/,shift,7;
  $from    =~ s/^://;
  $ircname =~ s/^://;
  my $user = Connection->new({nick => $nick,
			      user => $username,
			      host => $host,
			      ircname => $ircname,
			      server  => $this,
			      connected => time});
  my @modes = split//,$modestr;
  shift @modes;
  foreach my $mode (@modes) {
    $user->setmode($mode);
  }
  Utils::users()->{$user->nick()} = $user;
}

# :remote BC name creation modestr modeargs nicklistwmode
sub handle_burstchannel {
  my $this = shift;
  my($from,$command,$name,$creation,$modestr,@remainder) = split/\s+/,shift;
  $from  =~ s/^://;
  my $channel = Channel->new($name,$creation);
  $modestr =~ s/^\+//;
  foreach my $mode (split//,$modestr) {
    if(Channel::isvalidchannelmode($mode)) {
      $channel->{'modes'};
    }
  }
}

# :remote NICK nick hopcount timestamp username hostname servername ircname
sub handle_nick {
  my $this = shift;
  my $line = shift;
  $line =~ /^:(\S+)/;
  my $from = Utils::lookup($1);
  if(!ref($from)) {
    # network desyncage.
    return;
  }
  if($from->isa("Server")) {
    my($remote,$command,$nick,$hopcount,$timestamp,$username,$hostname,
       $servername,$ircname) = split(/\s+/,$line,9);
    # The user will add itself to the appropriate server itself
    my $user = User->new({ 'nick' => $nick,
			   'user' => $username,
			   'host' => $hostname,
			   'ircname' => $ircname,
			   'server' => Utils::lookup($servername),
			   'connected' => $timestamp });
    Utils::users()->{$user->nick()} = $user;
  } elsif($from->isa("User")) {
    # User is attempting to change their nick
    my($nick,$command,$newnick) = split(/\s+/,$line,3);
  } else {
    # network weirdness
  }
}

# :nick KILL target :excuse
sub handle_kill {
  my $this = shift;

}

# :remote QUIT nick excuse
sub handle_quit {
  my $this = shift;
  my($nick,$command,$excuse) = split(/\s+/,shift,3);
  # redistribute the quit message to other servers
  $nick =~ s/^://;
  $excuse =~ s/^://;

  my $user = Utils::lookup($nick);
  if(ref($user) && $user->isa("User")) {
    $user->quit($excuse);
  } else {
    Utils::syslog('notice', "Attempted to quit user who doesn't exist to us.");
    # woo! network desync, getting quits from users we don't know about
  }
}

sub handle_mode {
  my $this = shift;
  my($nick,$command,$mode) = split(/\s+/,shift,3);
  # redistribute the quit message to other servers
  $nick =~ s/^://;
  $mode =~ s/^://;
  my @s = split(" ",$mode,3);
  my $user = Utils::lookup($nick);
  my $channel = Utils::lookup($s[0]);
  my @arguments = split(" ",$s[2]);
  $channel->mode($user,$s[1],@arguments);
}


sub handle_privmsg { # added on june 27, 2010 :)
  my $this = shift;
  my($nick,$command,$msg) = split(/\s+/,shift,3);
  $nick =~ s/^://;
  my @s = split(" ",$msg);
  my $user = Utils::lookup($nick);
  my $channel = Utils::lookup($s[0]);
  my $message = $s[1];
  $message = substr($message,1);
  my $string = "PRIVMSG";
  $channel->privmsgnotice($string,$user,$message);
}

# :nick AWAY :excuse
sub handle_away {
  my $this = shift;
  my($nick,$command,$excuse) = split/\s+/,shift,3;
  $nick   =~ s/^://;
  $excuse =~ s/^://;
  my $user = Utils::lookup($nick);
  if(ref($user) && $user->isa("User")) {
    if(defined($excuse)) {
      $user->{'awaymsg'} = $excuse;
    } else {
      delete($user->{'awaymsg'});
    }
  } else {
    # network desyncage.
  }
}

# :nick JOIN :#channel1,#channel2,...
sub handle_join {
  my $this = shift;
  my($nick,$command,$channels) = split/\s+/,shift,3;
  $nick     =~ s/^://;
  $channels =~ s/^://;
  my $user = Utils::lookup($nick);
  if(ref($user) && $user->isa("User")) {
    my @channels = split/,/,$channels;
    foreach my $channel (@channels) {
      $channel = Utils::lookup($channel);
      if(ref($channel) && $channel->isa("Channel")) {
	$channel->force_join($user,$this);
      }
    }
  } else {
    # Network desyncage
  }
}

# :nick PART :#channel1,#channel2,...
sub handle_part {
  my $this = shift;
  my($nick,$command,$channels) = split/\s+/,shift,3;
  $nick     =~ s/^://;
  $channels =~ s/^://;
  my $user = Utils::lookup($nick);
  if(ref($user) && $user->isa("User")) {
    my @channels = split/,/,$channels;
    foreach my $channel (@channels) {
      $channel = Utils::lookup($channel);
      if(ref($channel) && $channel->isa("Channel")) {
	$channel->part($user,$this);
      }
    }
  } else {
    # Network desyncage
  }
}


#######################################################################

sub squit {
  my $this = shift;
  # we need to descend our tree of children, announcing the signoff of
  # every one of them, then announce the server disconnect(s) and dump
  # all the data structures. non-trivial.

  # for now:
  my $user;
  foreach $user ($this->users()) {
    $user->quit(join(' ',$this->parent->name,$this->name));
  }

  # Tell our parent we're gone
  $this->parent->removechildserver($this);
  # Remove us from the Servers hash
  delete(Utils::servers()->{$this->name()});
  # Close our socket if we have one
  if($this->{'socket'}) {
    &main::finishclient($this->{'socket'});
  }
}

#####################################################################
# SENDING THE SERVER STUFF
##########################

########################
# User state information

# Takes a User as the argument, sends the server all requisite information
# about that user.
sub nick {
  my $this = shift;
  my $user = shift;
  $this->senddata(join(' ',
		       ":".$this->parent->name,
		       "NICK",
		       $user->nick,
		       $user->server->hops+1,
		       $user->connected,
		       $user->username,
		       $user->host,
		       $user->server->name,
		       $user->ircname)."\r\n");
}

# Takes a user and their excuse as the arguments and informs
# $this of that user's disconnection
sub uquit {
  my $this = shift;
  my $user = shift;
  my $excuse = shift;
  $this->senddata(join(' ',
		       ":".$user->nick,
		       "QUIT",
		       $excuse)."\r\n");
}

###############
# Channel state

sub join {
  my $this    = shift;
  my $user    = shift;
  my $channel = shift;
  $this->senddata(join(' ',
		       ":".$user->nick,
		       "JOIN",
		       $channel->{'name'})."\r\n");
}

sub part {
  my $this    = shift;
  my $user    = shift;
  my $channel = shift;
  $this->senddata(join(' ',
		       ":".$user->nick,
		       "PART",
		       $channel->{'name'})."\r\n");
}

sub mode {
  my $this    = shift;
  my $from    = shift;
  my $target  = shift;
  my $str     = shift;
  $this->senddata(join(' ',
		       ":".($from->isa("User")?$from->{'nick'}:$from->{'name'}),
		       "MODE",
		       ($target->isa("User")?$target->{'nick'}:$target->{'name'}),
		       $str)."\r\n");
}

# Dispatch a wallops to this server
sub wallops {
  my $this = shift;
  my($from,$message) = @_;
  my $fromstr = "*unknown*";
  if($from->isa("User")) {
    $fromstr = $from->nick;
  } elsif($from->isa("Server")) {
    $fromstr = $from->name;
  }
  $this->senddata(join(' ',
		       ":".$fromstr,
		       "WALLOPS",
		       $message)."\r\n");
}

sub ping {
  my $this = shift;
  if($this->{'socket'}) {
    $this->{ping_waiting} = 1;
    $this->senddata(":".$this->{'server'}->name." PING :".$this->{'server'}->name."\r\n");
  } else {

  }
}

############################
# DATA ACCESSING SUBROUTINES
############################

# Get the name of this IRC server
sub name {
  my $this = shift;
  return $this->{'name'};
}

sub description {
  my $this = shift;
  return $this->{'description'};
}

# Returns an array of all the users on
# the server
sub users {
  my $this = shift;
  my @foo = values(%{$this->{users}});
  return @foo;
}

# Returns an array of all the children servers
sub children {
  my $this = shift;
  my @foo = values(%{$this->{children}});
  return @foo;
}

sub last_active {
  my $this = shift;
  return $this->{'last_active'};
}

sub connected {
  my $this = shift;
  return $this->{'connected'};
}

sub ping_in_air {
  my $this = shift;
  if($this->{'ping_waiting'}) {
    return 1;
  } else {
    return 0;
  }
}

# Returns the parent server of this server.
# (if you keep finding the parent of the parent
# until there isn't one, (this server) and then
# go back one, you'll have the server that a message
# has to be sent through to be routed properly.)
sub parent {
  my $this = shift;
  return $this->{'server'};
}

sub server {
  my $this = shift;
  return $this->{'server'};
}

# Returns the number of hops to reach the local
# server from the server represented by this
# server object.
sub hops {
  my $this = shift;
  return ($this->parent->hops+1);
}

###############################
# DATA MANIPULATING SUBROUTINES
###############################

# Tells the server that this person is now on it
sub adduser {
  my $this = shift;
  my $user = shift;
  $this->{'users'}->{$user->nick()} = $user;
}

sub removeuser {
  my $this = shift;
  my $user = shift;

  # This allows us to remove a user by their nick
  # or their User object.
  my $nick;
  if(ref($user)) {
    $nick = $user->nick();
  } else {
    $nick = $user;
  }

  Utils::syslog('notice', "server ".$this->name." is being requested to remove user $nick");

  delete($this->{'users'}->{$nick});
}

# Adds a server to the list of ones on this one.
sub addchildserver {
  my $this  = shift;
  my $child = shift;

  $this->{'children'}->{$child->name()} = $child;
}

# Removes a server from the list of ones on this one.
sub removechildserver {
  my $this  = shift;
  my $child = shift;

  my $name;
  if(ref($child)) {
    $name = $child->name();
  } else {
    $name = $child;
  }
  delete($this->{'children'}->{$name});
}

#####################################################################
# RAW, LOW-LEVEL OR MISC SUBROUTINES
####################################

# Add a command to the hash of commandname->subroutine refs
sub addcommand {
  my $this    = shift;
  my $command = shift;
  my $subref  = shift;
  $this->{'commands'}->{$command} = $subref;
}

sub senddata {
  my $this = shift;
  $this->{'outbuffer'}->{$this->{'socket'}} .= join('',@_);
}
sub ltrim ($) {
	my $string = shift;
	$string =~ s/^\s+//;
	return $string;
}
# Ri
1;
