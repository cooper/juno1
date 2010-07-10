#!/usr/bin/perl
#####################################################################
# Channel.pm                                                        #
# Created: Tue Sep 15 12:56:51 1998 by jay.kominek@colorado.edu     # 
# Revised: Wed Jun  5 12:59:27 2002 by jay.kominek@colorado.edu     #
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)          #
#                                                                   #
# Consult the file 'LICENSE' for the complete terms under which you #
# may use this file.                                                #
#                                                                   #
#####################################################################
#                   channel package - juno ircd                     #
#####################################################################

package Channel;
use Utils;
use User;
use Server;
use strict;
use UNIVERSAL qw(isa);

use Tie::IRCUniqueHash;

#####################
# CLASS CONSTRUCTOR #
#####################

# Expects to get the proper name of the channel as the first
# argument.
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };

  $this->{'name'} = shift;
  my %tmp = ();
  $this->{'bans'} = \%tmp;
  tie my %mutetmp, 'Tie::IRCUniqueHash';
  $this->{'mutes'} = \%mutetmp;
  $this->{'creation'} = shift || time();

  tie my %usertmp, 'Tie::IRCUniqueHash';
  $this->{'users'} = \%usertmp;
  tie my %opstmp,  'Tie::IRCUniqueHash';
  $this->{'ops'}   = \%opstmp;
  tie my %halfopstmp,  'Tie::IRCUniqueHash';
  $this->{'halfops'}   = \%halfopstmp;
  tie my %ownerstmp,  'Tie::IRCUniqueHash';
  $this->{'owners'}   = \%ownerstmp;
  tie my %adminstmp,  'Tie::IRCUniqueHash';
  $this->{'admins'}   = \%adminstmp;
  tie my %voicetmp,'Tie::IRCUniqueHash';
  $this->{'voice'} = \%voicetmp;
  tie my %jointimetmp,'Tie::IRCUniqueHash';
  $this->{'jointime'} = \%jointimetmp;

  bless($this, $class);
  return $this;
}

#####################################################################
# DATA ACCESSING SUBROUTINES
############################

sub users {
  my $this = shift;

  return values(%{$this->{'users'}});
}
sub bans {
  my $this = shift;
  return keys(%{$this->{'bans'}});
}
sub mutes {
  my $this = shift;
  return keys(%{$this->{'mutes'}});
}
# Sends the user /names output
sub names {
  my $this = shift;
  my $user = shift;

  my @lists;
  my($index,$count) = (0,0);
  foreach(sort
	  { $this->{'jointime'}->{$b} <=> $this->{'jointime'}->{$a} }
	  keys %{$this->{'users'}}) {
    if($count>60) { $index++; $count = 0; }
    my $nick = $this->{'users'}->{$_}->nick;
    if($this->isowner($this->{'users'}->{$_})) {
      $nick = "~".$nick;
    } elsif($this->isadmin($this->{'users'}->{$_})) {
      $nick = "&".$nick;
    } elsif($this->isop($this->{'users'}->{$_})) {
      $nick = "@".$nick;
    } elsif($this->ishalfop($this->{'users'}->{$_})) {
      $nick = "%".$nick;
    } elsif($this->hasvoice($this->{'users'}->{$_})) {
      $nick = "+".$nick;
    }


    push(@{$lists[$index]},$nick);
  }
  foreach(0..$index) {
    $user->senddata(":".$user->server->{name}." 353 ".$user->nick." = ".$this->{name}." :".join(' ',@{$lists[$_]})."\r\n");
  }
}

sub isvalidchannelmode {
  my $mode = shift;
  if($mode =~ /\W/) { return 0; }
  if(grep {/$mode/} ("b","i","k",
		     "l","m","n",
		     "o","s","t",
		     "v","a","q",
		     "h","Z","L",
		     "A","O"  )) {
    return 1;
  } else {
    return 0;
  }
}

# These functions manipulate binary modes on the channel.
# ismode returns 0 or 1 depending on whether or not the requested
#  mode is set on the channel now.
sub ismode {
  my $this = shift;
  my $mode = shift;
  if($this->{modes}->{$mode}==1) {
    return 1;
  } else {
    return 0;
  }
}

# do the dirty work for setmode and unsetmode
sub frobmode {
  my($this,$user,$mode,$val)=@_;

  if(!isvalidchannelmode($mode)) {
    $user->senddata(":".$user->server->{name}." 501 ".$user->nick." :Unknown mode flag \2$mode\2\r\n");
    return 0;
  }

  if($this->{'modes'}->{$mode}!=$val) {
    $this->{'modes'}->{$mode}=$val;
    return 1;
  } else {
    return 0;
  }
}

# setmode attempts to set the given mode to true. If the mode
#  is not already set, then it sets it. returns 1 if a mode
#  change was effected, 0 if the mode was already set.
sub setmode {
  frobmode(@_,1);
}

# unsetmode does the opposite of setmode.
sub unsetmode {
  frobmode(@_,0);
}
sub setlink {
	my $this = shift;
	my $user = shift;
	my $channel = shift;
	my $link = Utils::lookup($channel);
		if (isa($link,"Channel")) {
			unless ($link->{name} =~ /^\&/ && $this->{name} !~ /^\&/) {
				if ($link->isop($user)) {
					if (lc($this->{name}) eq lc($channel)) {
						$user->sendreply("609 $$this{name} $channel :You can't link a channel to itself");
					}
					else {
						if (defined($this->{'link'}) && lc($this->{'link'}) eq lc($channel)) {
							$user->sendreply("609 $$this{name} $channel :Target is already linked");
						}
						else {
							$this->setmode($user,"L");
							$this->{'link'} = $channel;
							return $channel;
						}
					}
				}
				else {
					$user->sendreply("609 $$this{name} $channel :You must be op in a channel to link it");
					return 0;
				}
			} else {
				$user->sendreply("609 $$this{name} $channel :Cannot link global channel to local channel");
				return 0;
			}
		} else {
			$user->sendreply("403 $$this{name} $channel :No such channel");
			return 0;
		}
}
sub unsetlink {
	my $this = shift;
	my $user = shift;
	my $link = $this->{link};
	delete($this->{link});
	undef($this->{link});
	$this->unsetmode($user, "L");
	return $link;
}
# These functions manipulate or view the ban list for $this channel
#  bans are stored as a hash, keyed on the mask. The value for that
#  hash{key} is a an array, the first item of which contains the name
#  of the person who set the ban, and the second item containing the
#  time the ban was set.
# XXX since when can a hash value be an array?
# setban takes a mask, and if it is not already present, adds it to
#  the list of bans on the channel.

sub setban {
# we actually *check* if a mask is somewhat valid, unlike before.
  my $this = shift;
  my $user = shift;
  my $mask = shift;
  my $full = $user->nick."!".$user->username."\@".$user->host;

	if ($mask =~ m/\@/) {
		if ($mask =~ m/\!/) {
			$mask = $mask; # cool story bro.
		}
		else {
			$mask = "*!".$mask;
		}
	}
	else {
		if ($mask =~ m/\!/) {
			$mask = $mask."@*";
		}
		else {
			$mask = $mask."!*@*";
		}
	}
    if(!defined($this->{'bans'}->{$mask})) {
	$mask = lc($mask); # this is easier... since capitalization doesn't matter with masks.
	$this->{'bans'}->{$mask} = [$full,time()];
	return $mask;
  } else {
    return 0; # already set
  }
}

sub setmute {
# we have mute! Added on july 1st, 2010
# we actually *check* if a mask is somewhat valid, unlike before.
  my $this = shift;
  my $user = shift;
  my $mask = shift;
  my $full = $user->nick."!".$user->username."\@".$user->host;

	if ($mask =~ m/\@/) {
		if ($mask =~ m/\!/) {
			$mask = $mask; # cool story bro.
		}
		else {
			$mask = "*!".$mask;
		}
	}
	else {
		if ($mask =~ m/\!/) {
			$mask = $mask."@*";
		}
		else {
			$mask = $mask."!*@*";
		}
	}
    if(!defined($this->{'mutes'}->{$mask})) {
	$mask = lc($mask); # this is easier... since capitalization doesn't matter with masks.
	$this->{'mutes'}->{$mask} = [$full,time()];
	return $mask;
  } else {
    return 0; # already set
  }
}

# Removes a ban mask from the current 
sub unsetban {
  my $this = shift;
  my $user = shift;
  my $mask = shift;
  my $mask = lc($mask);

  if(defined($this->{bans}->{$mask})) {
    delete($this->{bans}->{$mask});
    return $mask;
  } else {
    return 0;
  }
}
sub unsetmute {
  my $this = shift;
  my $user = shift;
  my $mask = shift;
  my $mask = lc($mask);

  if(defined($this->{mutes}->{$mask})) {
    delete($this->{mutes}->{$mask});
    return $mask;
  } else {
    return 0;
  }
}
# Takes a User object and returns true if that user
# is an op on this channel.
sub isop {
  my $this = shift;
  my $user = shift;
  if(defined($this->{ops}->{$user->nick()})) {
    return 1;
  } else {
    return 0;
  }
}
sub ishalfop {
# as of may 2010, we have halfop support :)
  my $this = shift;
  my $user = shift;
  if(defined($this->{halfops}->{$user->nick()})) {
    return 1;
  } else {
    return 0;
  }
}
sub isadmin {
# admin added may 2010
  my $this = shift;
  my $user = shift;
  if(defined($this->{admins}->{$user->nick()})) {
    return 1;
  } else {
    return 0;
  }
}
sub isowner {
# what good is halfop without owner and admin as well? we now have all 5 prefixes :D
  my $this = shift;
  my $user = shift;
  if(defined($this->{owners}->{$user->nick()})) {
    return 1;
  } else {
    return 0;
  }
}
sub setop {
# the setowner, setadmin, setop, sethalfop, and setvoice subroutines were changed entirely.
# I tested several times to make sure halfops can't give op, ops can't give admin, etc
# i think it's all good :)
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
	if ((ref($ret) && isa($ret,"User"))) {
		if (defined($this->{'users'}->{$ret->nick()})) {
			if ($this->isop($user) || $user->ismode('O')) {
				if (!defined($this->{ops}->{$ret->nick()})) {
					$this->{ops}->{$ret->nick()} = $user;
					return $ret->nick;
				}
				else {
					return 0;
				}
			}
			else {
				$user->sendreply("482 $$this{name} :You're not a channel operator.");
				# technically, non ops/halfops can't set modes at all, so this isn't necessary
				# but we might as well check here too
				return 0;
			}
		}
		else {
			$user->sendnumeric($user->server,441,$target,$this->{name},"They aren't on the channel");
			return 0;
		}
	}
	else {
		$user->sendnumeric($user->server,401,$target,"No such nick");
		return 0;		
	}
}

sub unsetop {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
  if(!(ref($ret) && isa($ret,"User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return 0;
  }
  if(!defined($this->{'users'}->{$ret->nick()})) {
    $user->sendnumeric($user->server,441,$target,$this->{name},
		       "They aren't on the channel");
    return 0;
  }
  if(!$this->isop($user) && !$user->ismode('O')) {
   $user->sendreply("482 $$this{name} :You're not a channel operator.");
    return 0;
  }
  if(defined($this->{ops}->{$ret->nick()})) {
    delete($this->{ops}->{$ret->nick()});
    return $ret->nick;
  } else {
    return 0;
  }
}
sub sethalfop {
# the setowner, setadmin, setop, sethalfop, and setvoice subroutines were changed entirely.
# I tested several times to make sure halfops can't give op, ops can't give admin, etc
# i think it's all good :)
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
	if ((ref($ret) && isa($ret,"User"))) {
		if (defined($this->{'users'}->{$ret->nick()})) {
			if ($this->isop($user) || $user->ismode('O')) {
				if (!defined($this->{halfops}->{$ret->nick()})) {
					$this->{halfops}->{$ret->nick()} = $user;
					return $ret->nick;
				}
				else {
					return 0;
				}
			}
			else {
				$user->sendreply("482 $$this{name} :You're not a channel operator.");
				return 0;
			}
		}
		else {
			$user->sendnumeric($user->server,441,$target,$this->{name},"They aren't on the channel");
			return 0;
		}
	}
	else {
		$user->sendnumeric($user->server,401,$target,"No such nick");
		return 0;		
	}
}

sub unsethalfop {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
  if(!(ref($ret) && isa($ret,"User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return 0;
  }
  if(!defined($this->{'users'}->{$ret->nick()})) {
    $user->sendnumeric($user->server,441,$target,$this->{name},
		       "They aren't on the channel");
    return 0;
  }
  if(!$this->isop($user) && !$user->ismode('O')) {
   $user->sendreply("482 $$this{name} :You're not a channel operator.");
    return 0;
  }
  if(defined($this->{halfops}->{$ret->nick()})) {
    delete($this->{halfops}->{$ret->nick()});
    return $ret->nick;
  } else {
    return 0;
  }
}

sub setadmin {
# the setowner, setadmin, setop, sethalfop, and setvoice subroutines were changed entirely.
# I tested several times to make sure halfops can't give op, ops can't give admin, etc
# i think it's all good :)
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
	if ((ref($ret) && isa($ret,"User"))) {
		if (defined($this->{'users'}->{$ret->nick()})) {
			if ($this->isowner($user) || $user->ismode('O')) {
				if (!defined($this->{admins}->{$ret->nick()})) {
					$this->{admins}->{$ret->nick()} = $user;
					return $ret->nick;
				}
				else {
					return 0;
				}
			}
			else {
				$user->sendreply("482 $$this{name} :You're not a channel owner.");
				return 0;
			}
		}
		else {
			$user->sendnumeric($user->server,441,$target,$this->{name},"They aren't on the channel");
			return 0;
		}
	}
	else {
		$user->sendnumeric($user->server,401,$target,"No such nick");
		return 0;		
	}
}

sub unsetadmin {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
  if(!(ref($ret) && isa($ret,"User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return 0;
  }
  if(!defined($this->{'users'}->{$ret->nick()})) {
    $user->sendnumeric($user->server,441,$target,$this->{name},
		       "They aren't on the channel");
    return 0;
  }
  if(!$this->isowner($user) && !$user->ismode('O') && lc($user->nick) ne lc($target)) {
   $user->sendreply("482 $$this{name} :You're not a channel owner.");
    return 0;
  }
  if(defined($this->{admins}->{$ret->nick()})) {
    delete($this->{admins}->{$ret->nick()});
    return $ret->nick;
  } else {
    return 0;
  }
}

sub setowner {
# the setowner, setadmin, setop, sethalfop, and setvoice subroutines were changed entirely.
# I tested several times to make sure halfops can't give op, ops can't give admin, etc
# i think it's all good :)
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
	if ((ref($ret) && isa($ret,"User"))) {
		if (defined($this->{'users'}->{$ret->nick()})) {
			if ($this->isowner($user) || $user->ismode('O')) {
				if (!defined($this->{owners}->{$ret->nick()})) {
					$this->{owners}->{$ret->nick()} = $user;
					return $ret->nick;
				}
				else {
					return 0;
				}
			}
			else {
				$user->sendreply("482 $$this{name} :You're not a channel owner.");
				return 0;
			}
		}
		else {
			$user->sendnumeric($user->server,441,$target,$this->{name},"They aren't on the channel");
			return 0;
		}
	}
	else {
		$user->sendnumeric($user->server,401,$target,"No such nick");
		return 0;		
	}
}
sub firstjoin {
# this subroutine replaces force_join, as we can't set op without a user unless defined by the server (here)
# and it was checking for op, when there was nothing to check. "you're not channel operator" when we were joining
# and this subroutine is the exact same without the op check
  my $this   = shift;
  my $user   = shift;
  my $server = shift;

  $this->{'ops'}->{$user->nick()} = $user;
  $this->{'users'}->{$user->nick()} = $user;
  $this->{'jointime'}->{$user->nick()} = time;
  $user->{'channels'}->{$this->{name}} = $this;
  $this->setmode($user,"n");
  $this->setmode($user,"t");
  User::multisend(":$$user{nick}!$$user{user}\@$$user{host} JOIN>:$$this{name}",
		  values(%{$this->{'users'}}));
  User::multisend(":".$user->server->name." MODE>$$this{name} +nt $$user{nick}",
		  values(%{$this->{'users'}}));
  foreach my $iserver ($Utils::thisserver->children) {
    if($iserver ne $server) {
      $iserver->join($user,$this);
    }
  }
    return $user->nick;
}


sub unsetowner {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
  if(!(ref($ret) && isa($ret,"User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return 0;
  }
  if(!defined($this->{'users'}->{$ret->nick()})) {
    $user->sendnumeric($user->server,441,$target,$this->{name},
		       "They aren't on the channel");
    return 0;
  }

  if(!$this->isowner($user) && !$user->ismode('O')) {
   $user->sendreply("482 $$this{name} :You're not a channel owner.");
    return 0;
  }
  if(defined($this->{owners}->{$ret->nick()})) {
    delete($this->{owners}->{$ret->nick()});
    return $ret->nick;
  } else {
    return 0;
  }
}

# Takes a User object and tells you if it has a voice on
# this channel.
sub hasvoice {
  my $this = shift;
  my $user = shift;
  if(defined($this->{voice}->{$user->nick()})) {
    return 1;
  } else {
    return 0;
  }
}

sub setvoice {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
	if ((ref($ret) && isa($ret,"User"))) {
		if (defined($this->{'users'}->{$ret->nick()})) {
			if ($this->isop($user) || $this->ishalfop($user) || $user->ismode('O')) {
				if (!defined($this->{voice}->{$ret->nick()})) {
					$this->{voice}->{$ret->nick()} = $user;
					return $ret->nick;
				}
				else {
					return 0;
				}
			}
			else {
				$user->sendreply("482 $$this{name} :You're not a channel operator.");
				return 0;
			}
		}
		else {
			$user->sendnumeric($user->server,441,$target,$this->{name},"They aren't on the channel");
			return 0;
		}
	}
	else {
		$user->sendnumeric($user->server,401,$target,"No such nick");
		return 0;		
	}
}

sub unsetvoice {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
  if(!(ref($ret) && isa($ret,"User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return 0;
  }
  if(!defined($this->{'users'}->{$ret->nick()})) {
    $user->sendnumeric($user->server,441,$target,$this->{name},
		       "They aren't on the channel");
    return 0;
  }
  if(defined($this->{voice}->{$ret->nick()})) {
    delete($this->{voice}->{$ret->nick()});
    return $ret->nick;
  } else {
    return 0;
  }
}

#####################################################################
# DATA MANIPULATING SUBROUTINES
###############################

# handle a MODE command from a user - can be mode check or mode change
sub mode {
  my($this,$user,$modestr,@arguments)=@_;
  my @modebytes = split(//,$modestr);
  my(@accomplishedset,@accomplishedunset,@accomplishedargs);
  my $state = 1;
  my $arg;

  # if it's a mode check, send the nf0z
  if(!defined($modestr)) {
    my(@modes,@args);
    foreach(keys(%{$this->{'modes'}})) {
      next if(!$this->{'modes'}->{$_}); # don't show unset modes

      if($_ eq "k") {
	if($user->onchan($this)) {
	  push(@args,  $this->{'key'});
	}
      } elsif($_ eq "l") {
	push(@args,  $this->{'limit'});
      } elsif($_ eq "L") {
	push(@args,  $this->{'link'});
      }
      push(@modes, $_);
    }
    $user->sendnumeric($user->server,324,($this->{name},"+".join('',@modes),@args),undef);
    $user->sendnumeric($user->server,329,($this->{name},$this->{'creation'}),undef);
    return;
  } elsif($modestr eq 'b' or ($modestr eq '+b' and $#arguments == -1)) {
    foreach(keys(%{$this->{'bans'}})) {
      my @bandata = @{$this->{'bans'}->{$_}};
      $user->sendnumeric($user->server,367,($this->{name},$_,@bandata),undef);
    }
    $user->sendnumeric($user->server,368,($this->{name}),"End of channel ban list");
    return;
  } elsif($modestr eq 'Z' or ($modestr eq '+Z' and $#arguments == -1)) {
    foreach(keys(%{$this->{'mutes'}})) {
      my @mutedata = @{$this->{'mutes'}->{$_}};
      $user->sendnumeric($user->server,367,($this->{name},$_,@mutedata),undef);
    }
    $user->sendnumeric($user->server,368,($this->{name}),"End of channel mute list");
    return;
  }

  if(!$this->isop($user) && !$user->ismode('O') && !$this->ishalfop($user)) {
    $user->sendreply("482 $$this{name} :You're not a channel operator.");
    return;
  }

  foreach(@modebytes) {
    if($_ eq "+") {
      $state = 1;
    } elsif($_ eq "-") {
      $state = 0;
    } else {
      if($_=~/[bZoahqvlkLA]/ &&!($_ eq 'l' && !$state)) {
	if ($_ eq "L" && !$state && $this->ismode("L")) { $this->unsetlink($user); push(@accomplishedunset, $_); }
	$arg=shift(@arguments);
	next if(!defined($arg));
      } else {
	push(@accomplishedset,$_) if($state && $this->setmode($user,$_));
	push(@accomplishedunset,$_) if(!$state && $this->unsetmode($user,$_));
	next;
      }
      
      if($_ eq "b") {
	$arg=$this->setban($user,$arg) if($state);
	$arg=$this->unsetban($user,$arg) if(!$state);
      } elsif($_ eq "Z") {
	$arg=$this->setmute($user,$arg) if($state);
	$arg=$this->unsetmute($user,$arg) if(!$state);
      } elsif($_ eq "q") {
	$arg=$this->setowner($user,$arg) if($state);
	$arg=$this->unsetowner($user,$arg) if(!$state);
      } elsif($_ eq "a") {
	$arg=$this->setadmin($user,$arg) if($state);
	$arg=$this->unsetadmin($user,$arg) if(!$state);
      } elsif($_ eq "o") {
	$arg=$this->setop($user,$arg) if($state);
	$arg=$this->unsetop($user,$arg) if(!$state);
      } elsif($_ eq "h") {
	$arg=$this->sethalfop($user,$arg) if($state);
	$arg=$this->unsethalfop($user,$arg) if(!$state);
      } elsif($_ eq "v") {
	$arg=$this->setvoice($user,$arg) if($state);
	$arg=$this->unsetvoice($user,$arg) if(!$state);
      } elsif($_ eq "L") {
	$arg=$this->setlink($user, $arg) if($state);
	$arg=$this->unsetlink($user, $arg) if(!$state);
      } elsif($_ eq "l") {
	if($arg =~ /\D/) {
	  $user->sendreply("467 $$this{name} :Channel limit value \2$arg\2 is nonnumeric");
	  next;
	} else {
	  $this->setmode($user,'l');
	  $this->{'limit'} = $arg;
	}
      } elsif($_ eq "k") {
	if($state) {
	  if($this->ismode('k')) {
	    $user->sendreply("467 $$this{name} :Channel key already set");
	    undef $arg;
	  } else {
	    $this->setmode($user,'k');
	    $this->{'key'} = $arg;
	  }
	} else {
	  if($arg ne $this->{key} || !($this->unsetmode($user, "k"))) {
	    undef $arg;
	  }
	}
      }
      if($arg) {
	push(@accomplishedset,$_) if($state);
	push(@accomplishedunset,$_) if(!$state);
	push(@accomplishedargs,$arg);
      }
    }
  }

  if($#accomplishedset>=0 || $#accomplishedunset>=0) {
    my $changestr;
    if($#accomplishedset>=0) {
      $changestr = "+".join('',@accomplishedset);
    }
    if($#accomplishedunset>=0) {
      $changestr .= "-".join('',@accomplishedunset);
    }
    if($#accomplishedargs>=0) {
      $changestr .= join(' ','',@accomplishedargs);
    }
    User::multisend(":$$user{nick}!$$user{user}\@$$user{host}".
		    " MODE>$$this{name} $changestr",
		    values(%{$this->{'users'}}));
    foreach my $server ($user->server->children) {
      $server->mode($user,$this,$changestr);
    }
  }
}

sub topic {
  my $this = shift;
  my $user = shift;
  my $topic = shift;
  if(defined($user) && defined($topic)) {
    unless($this->ismode('t') && (!($this->isop($user) ||
				    $user->ismode('S') || $this->ishalfop($user)))) {
      $this->{'topic'}        = $topic;
      $this->{topicsetter}  = $user->nick;
      $this->{topicsettime} = time();
      foreach(keys(%{$this->{'users'}})) {
	if($this->{'users'}->{$_}->islocal()) {
	  $this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." TOPIC ".$this->{name}." :$topic\r\n");
	}
      }
    } else {
      $user->senddata(":".$user->server->{name}." 482 ".$user->nick." ".$this->{name}." :You're not a channel operator\r\n");
    }
  } else {
    if($this->{'topic'}) {
      return ($this->{'topic'},$this->{topicsetter},$this->{topicsettime});
    } else {
      return undef;
    }
  }
}

# Called when a local user wants to try and join the channel
# (This one does checking and stuff)
sub join {
  my $this = shift;
  my $user = shift;
  my @keys = @_;
  my $hasinvitation = 0;

  my($fu,$bar) = ($user->nick,$this->{name});

  if(defined($this->{hasinvitation}->{$user})) {
    $hasinvitation = 1;
    delete($this->{hasinvitation}->{$user});
  }

  # Test to see if the user needs an invitation [and doesn't have
  # it/isn't godlike]
  if($this->ismode('i') && (!$hasinvitation) && !$user->ismode('S')) {
    Connection::sendreply($user, "473 $this->{name} :Cannot join channel (+i)");
    return;
  }

  # If the user is invited, [or godlike] then they can bypass the key,
  # limit, and bans
  unless($hasinvitation || $user->ismode('S')) {
    # Test to see if the user knows the channel key
    if($this->ismode('k')) {
      unless(grep {$_ eq $this->{key}} @keys) {
	Connection::sendreply($user, "475 $this->{name} :Cannot join channel. Requires keyword. (+k)");
	return;
      }
    }
  
    # Test to see if the channel is over the current population limit.
  unless($hasinvitation || $user->ismode('O')) {
    if(($this->ismode('l')) &&
       ((1+scalar keys(%{$this->{'users'}}))>$this->{limit})) {
      Connection::sendreply($user, "471 $this->{name} :Cannot join channel. Population limit reached. (+l)");
	if ($this->ismode('L')) {
		my $link = Utils::lookup($this->{link});
		if ($link->ismode("L") && $link->ismode("l")) {
			if (1+scalar keys(%{$link->{'users'}})>$link->{limit}) {
     				Connection::sendreply($user, "NOTICE $user->{nick} $this->{name} :Multiple links - you're not going anywhere.");
			}
			else {
				$user->handle_join("JOIN ".$this->{link},$this->{link});
				Connection::sendreply($user, "NOTICE $user->{nick} $this->{name} :Forwarding channel");
			}
		}
		else {
			$user->handle_join("JOIN ".$this->{link},$this->{link});
			Connection::sendreply($user, "NOTICE $user->{nick} $this->{name} :Forwarding channel");
		}
	}
      return;
    }
  }

    # Test for bans, here
    my @banmasks = keys(%{$this->{bans}});
    my(@banregexps, $mask);
    $mask = $user->nick."!".$user->username."\@".$user->host;
    foreach(@banmasks) {
      my $regexp = $_;
      $regexp =~ s/\./\\\./g;
      $regexp =~ s/\?/\./g;
      $regexp =~ s/\*/\.\*/g;
      $regexp = "^".$regexp."\$";
      push(@banregexps,$regexp);
    }
    if(grep {$mask =~ /$_/} @banregexps) {
      $user->sendnumeric($user->server,474,$this->{name},"Cannot join channel You're banned. (+b)");
      return;
    }
  }

  #do the actual join
  if(0==scalar keys(%{$this->{'users'}})) {
	$this->firstjoin($user,$user->server);
  }
  else {
	$this->force_join($user,$user->server);
  }

  $user->sendnumeric($user->server,332,$this->{'name'},$this->{'topic'}) if defined $this->{'topic'};
  $user->sendnumeric($user->server,333,$this->{'name'},$this->{'topicsetter'},$this->{'topicsettime'},undef) if defined $this->{'topicsetter'};
  if(defined($this->{'topic'})) {
    $this->topic($user);
  }
  $this->names($user);
  $user->sendnumeric($user->server,366,$this->{name},"End of /NAMES list.");
}

# Called by (servers) to forcibly add a user, does no checking.
sub force_join {
  my $this = shift;
  my $user = shift;
  my $server = shift; # the server that is telling us about the
                      # user connecting has to tell us what it is
                      # so that when we propogate the join on,
                      # we don't tell it.

  Utils::channels()->{$this->{name}} = $this;
  $this->{'users'}->{$user->nick()} = $user;
  $this->{'jointime'}->{$user->nick()} = time;
  $user->{'channels'}->{$this->{name}} = $this;
  User::multisend(":$$user{nick}!$$user{user}\@$$user{host} JOIN>:$$this{name}",
		  values(%{$this->{'users'}}));

  
  foreach my $iserver ($Utils::thisserver->children) {
    if($iserver ne $server) {
      $iserver->join($user,$this);
    }
  }
}

# This one is called when a user leaves
sub part {
  my($this,$user,$server)=@_;
  my @foo;

  foreach my $iserver ($Utils::thisserver->children) {
    if($iserver ne $server) {
      $iserver->part($user,$this);
    }
  }

  @foo=$this->notifyofquit($user);

  User::multisend(":$$user{nick}!$$user{user}\@$$user{host} PART>$$this{name}",
		  @foo,$user);
}

sub kick {
  my($this,$user,$target,$excuse)=@_;
  my @foo;
  my $sap = Utils::lookupuser($target,1);

  if(!$this->isop($user) && !$this->ishalfop($user) && !$user->ismode('O')) {
    $user->sendnumeric($user->server,482,$this->{name},"You are not a channel operator");
    return;
  }
  if(!$this->isowner($user) && $this->isowner($sap) && !$this->ismode('O')) {
    $user->sendnumeric($user->server,482,$this->{name},"You are not a channel owner");
    return;
  }
  if(!$this->isowner($user) && $this->isadmin($sap) && !$this->ismode('O')) {
    $user->sendnumeric($user->server,482,$this->{name},"You are not a channel owner");
    return;
  }
  if($this->ishalfop($user) && !$this->isop($user) && $this->isowner($sap) && !$this->ismode('O')) {
    $user->sendnumeric($user->server,482,$this->{name},"You are not a channel owner");
    return;
  }
  if($this->ishalfop($user) && !$this->isop($user) && $this->isadmin($sap) && !$this->ismode('O')) {
    $user->sendnumeric($user->server,482,$this->{name},"You are not a channel owner");
    return;
  }
  if($this->ishalfop($user) && !$this->isop($user) && $this->isop($sap) && !$this->ismode('O')) {
    $user->sendnumeric($user->server,482,$this->{name},"You are not a channel operator");
    return;
  }
  if((!defined($sap)) || (!$sap->isa("User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return;
  }

  if(!$sap->onchan($this)) {
    $user->sendnumeric($user->server,441,$target,"Nick $target is not on $$this{name}");
    return;
  }

  if($sap->ismode('S')) {
      $user->sendnumeric($user->server,484,$target,"You may not kick network services.");
    return;
  }

  # don't we have to communicate this to other servers somehow ???
  # TODO add that later :p

  @foo=$this->notifyofquit($sap);
  User::multisend(":$$user{nick}!$$user{user}\@$$user{host}"
		  ." KICK>$$this{name} $$sap{nick} :$excuse",@foo,$sap);
}

sub invite {
  my $this   = shift;
  my $from   = shift;
  my $target = shift;
  
  if($target->onchan($this)) {
    $from->sendnumeric($from->server,443,$target->nick,$this->{name},"is already on channel");
    return;
  }
  if($this->isop($from) || $from->ismode('S')) {
    $this->{'hasinvitation'}->{$target} = 1;
    $target->addinvited($this);
    $target->invite($from,$this->{name});
    $from->sendnumeric($from->server,341,$target->nick,$this->{name},undef);
  } else {
    $from->sendnumeric($from->server,482,$this->{name},"You are not a channel operator");
  }
}

sub nickchange {
  my $this = shift;
  my $user = shift;

  if($this->{'ops'}->{$user->{'oldnick'}}) {
    delete $this->{'ops'}->{$user->{'oldnick'}};
    $this->{'ops'}->{$user->nick()} = $user;
  }

  if($this->{'halfops'}->{$user->{'oldnick'}}) {
    delete $this->{'halfops'}->{$user->{'oldnick'}};
    $this->{'halfops'}->{$user->nick()} = $user;
  }
  if($this->{'admins'}->{$user->{'oldnick'}}) {
    delete $this->{'admins'}->{$user->{'oldnick'}};
    $this->{'admins'}->{$user->nick()} = $user;
  }  
  if($this->{'owners'}->{$user->{'oldnick'}}) {
    delete $this->{'owners'}->{$user->{'oldnick'}};
    $this->{'owners'}->{$user->nick()} = $user;
  }  
  if($this->{'voice'}->{$user->{'oldnick'}}) {
    delete $this->{'voice'}->{$user->{'oldnick'}};
    $this->{'voice'}->{$user->nick()} = $user;
  }
  
  $_ = $this->{'jointime'}->{$user->{'oldnick'}};
  delete($this->{'jointime'}->{$user->{'oldnick'}});
  $this->{'jointime'}->{$user->nick()} = $_;

  delete($this->{'users'}->{$user->{'oldnick'}});
  $this->{'users'}->{$user->nick()} = $user;

  return $this->{'users'};
}

#####################################################################
# COMMUNICATION SUBROUTINES
###########################

sub checkvalidtosend {
  my $this = shift;
  my $user = shift;

  if($this->ismode('n') && (!defined($this->{'users'}->{$user->nick()}))) {
    $user->senddata(":".$user->server->{name}." 404 ".$user->nick." ".$this->{name}." Cannot send to channel. No external messages. (+n)\r\n");
    return 0;
  }

  if($this->ismode('m')) {
    if((!$this->hasvoice($user)) && (!($this->isop($user) ||
				       $user->ismode('S')))) {
      $user->senddata(":".$user->server->{name}." 404 ".$user->nick." ".$this->{name}." Cannot send to channel. Channel is moderated. (+m)\r\n");
      return 0;
    }
  }
    my @banmasks = keys(%{$this->{bans}});
    my(@banregexps, $mask);
    $mask = $user->nick."!".$user->username."\@".$user->host;
    $mask = lc($mask);
    foreach(@banmasks) {
      my $regexp = $_;
      $regexp =~ s/\./\\\./g;
      $regexp =~ s/\?/\./g;
      $regexp =~ s/\*/\.\*/g;
      $regexp = "^".$regexp."\$";
      $regexp = lc($regexp);
      push(@banregexps,$regexp);
    }
    if(grep {$mask =~ /$_/} @banregexps) {
      $user->senddata(":".$user->server->{name}." 404 ".$user->nick." ".$this->{name}." Cannot send to channel. You're banned. (+b)\r\n");
      return 0;
    }
    my @mutemasks = keys(%{$this->{mutes}});
    my(@muteregexps, $mask);
    $mask = $user->nick."!".$user->username."\@".$user->host;
    $mask = lc($mask);
    foreach(@mutemasks) {
      my $regexp = $_;
      $regexp =~ s/\./\\\./g;
      $regexp =~ s/\?/\./g;
      $regexp =~ s/\*/\.\*/g;
      $regexp = "^".$regexp."\$";
      $regexp = lc($regexp);
      push(@muteregexps,$regexp);
    }
    if(grep {$mask =~ /$_/} @muteregexps) {
      $user->senddata(":".$user->server->{name}." 404 ".$user->nick." ".$this->{name}." Cannot send to channel. You're muted. (+Z)\r\n");
      return 0;
    }

  return 1;
}

# Sends a private message or notice to everyone on the channel.
sub privmsgnotice {
  my $this = shift;
  my $string = shift;
  my $user = shift;
  my $msg  = shift;

  unless($this->checkvalidtosend($user)) {
    return;
  }

  foreach(keys(%{$this->{'users'}})) {
    if(($this->{'users'}->{$_} ne $user)&&($this->{'users'}->{$_}->islocal())) {
      $this->{'users'}->{$_}->senddata(
				       sprintf(":%s!%s\@%s %s %s :%s\r\n",
					       $user->{'nick'},
					       $user->{'username'},
					       $user->{'host'},
					       $string,
					       $this->{name},
					       $msg));
    }
  }
  # We need something to disseminate the message to other servers
}

# This function does two things. First, it removes a user from a channel.
# Second, it figures out what other users on the channel should be informed,
# but it does not inform them. It returns a list of the other users on this
# server that should be informed.
# NB the user who was removed is *not* in the list returned.
sub notifyofquit {
  my($chan,$user)=@_;
  my @inform;

  # make the user go away
  delete($user->{'channels'}->{$chan->{'name'}});
  delete($chan->{'users'}->{$user->nick()});
  delete($chan->{'ops'}->{$user->nick()});
  delete($chan->{'admins'}->{$user->nick()});
  delete($chan->{'owners'}->{$user->nick()});
  delete($chan->{'halfops'}->{$user->nick()});
  delete($chan->{'voice'}->{$user->nick()});
  delete($chan->{'jointime'}->{$user->nick()});

  # if the channel is now empty, it needs to go away too.
  if(0==scalar keys(%{$chan->{'users'}})) {
    delete(Utils::channels()->{$chan->{name}});
#    return (undef);
  }

  # now find out who gets to know about it
  foreach(keys(%{$chan->{'users'}})) {
    push(@inform,$chan->{'users'}->{$_}) if($chan->{'users'}->{$_}->islocal());
  }

  return @inform;
}

1;
