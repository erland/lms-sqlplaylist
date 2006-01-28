# 				SQLPlayList plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the Random Mix plugin:
#    Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
#    New world order by Dan Sully - <dan | at | slimdevices.com>
#    Fairly substantial rewrite by Max Spicer

#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package Plugins::SQLPlayList::Plugin;

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);

my %stopcommands = ();
# Random play type for each client
my %type         = ();
# Display text for each mix type
my %displayText  = ();
my $htmlTemplate = 'plugins/SQLPlayList/sqlplaylist_list.html';
my $ds = Slim::Music::Info::getCurrentDataStore();

sub getDisplayName {
	return 'PLUGIN_SQLPLAYLIST';
}

# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $find, $limit, $addOnly) = @_;

	debugMsg("Starting random selection of $limit items for type: $type\n");
	
	my $items = getTracksForPlaylist($client,$type,$limit);

	debugMsg("Find returned ".(scalar @$items)." items\n");
			
	# Pull the first track off to add / play it if needed.
	my $item = shift @{$items};

	if ($item && ref($item)) {
		my $string = $item->title;
		debugMsg("".($addOnly ? 'Adding' : 'Playing')."$type: $string, ".($item->id)."\n",

		# Replace the current playlist with the first item / track or add it to end
		$client->execute(['playlist', $addOnly ? 'addtracks' : 'loadtracks',
		                  sprintf('track=%d', $item->id)]));
		
		# Add the remaining items to the end
		if (! defined $limit || $limit > 1) {
			debugMsg("Adding ".(scalar @$items)." tracks to end of playlist\n");
			$client->execute(['playlist', 'addtracks', 'listRef', $items]);
		}
	} 
	
}


# Add random tracks to playlist if necessary
sub playRandom {
	# If addOnly, then track(s) are appended to end.  Otherwise, a new playlist is created.
	my ($client, $type, $addOnly) = @_;

	# disable this during the course of this function, since we don't want
	# to retrigger on commands we send from here.
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);

	debugMsg("playRandom called with type $type\n");
	
	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;
	debugMsg("$songsRemaining songs remaining, songIndex = $songIndex\n");

	# Work out how many items need adding
	my $numItems = 0;

	if ($type ne 'disable') {
		# Add new tracks if there aren't enough after the current track
		my $numRandomTracks = Slim::Utils::Prefs::get('plugin_sqlplaylist_number_of_tracks');
		if (! $addOnly) {
			$numItems = $numRandomTracks;
		} elsif ($songsRemaining < $numRandomTracks - 1) {
			$numItems = $numRandomTracks - 1 - $songsRemaining;
		} else {
			debugMsg("$songsRemaining items remaining so not adding new track\n");
		}
	}

	if ($numItems) {
		unless ($addOnly) {
			Slim::Control::Command::execute($client, [qw(stop)]);
			Slim::Control::Command::execute($client, [qw(power 1)]);
		}
		Slim::Player::Playlist::shuffle($client, 0);
		
		# String to show with showBriefly
		my $string = '';

		$string = $type;

		# Strings for non-track modes could be long so need some time to scroll
		my $showTime = 5;
		
		# Add tracks 
		my $find;
		findAndAdd($client,
                        $type,
                        $find,
                        $numItems,
			            # 2nd time round just add tracks to end
					    $addOnly);

		# Do a show briefly the first time things are added, or every time a new album/artist/year
		# is added
		if (!$addOnly || $type ne $type{$client}) {
			# Don't do showBrieflys if visualiser screensavers are running as the display messes up
			if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
				$client->showBriefly(string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'),
									 $string, $showTime);
			}
		}

		# Never show random as modified, since its a living playlist
		$client->currentPlaylistModified(0);		
	}
	
	if ($type eq 'disable') {
		Slim::Control::Command::clearExecuteCallback(\&commandCallback);
		debugMsg("cyclic mode ended\n");
		# Don't do showBrieflys if visualiser screensavers are running as the display messes up
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
			$client->showBriefly(string('PLUGIN_SQLPLAYLIST'), string('PLUGIN_SQLPLAYLIST_DISABLED'));
		}
		$type{$client} = undef;
	} else {
		debugMsg("Playing continuous $type mode with ".Slim::Player::Playlist::count($client)." items\n");
		Slim::Control::Command::setExecuteCallback(\&commandCallback);
		
		# Do this last to prevent menu items changing too soon
		$type{$client} = $type;
		# Make sure that changes in menu items are displayed
		#$client->update();
	}
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	if ($item ne $type{$client}) {
		return [undef, Slim::Display::Display::symbol('notesymbol')];
	} else {
		return [undef, undef];
	}
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	debugMsg("".($add ? 'Add' : 'Play')."$item\n");
	
	# Don't play/add a mix that's already enabled
	if ($item ne $type{$client}) {	
		playRandom($client, $item, $add);
	}
}

sub getPlayLists {
	my $client = shift;
	
	my $playlistDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
	debugMsg("Searching for playlists in: $playlistDir\n");
	
	if (!defined $playlistDir || !-d $playlistDir) {
		debugMsg("Skipping playlist folder scan - playlistdir is undefined.\n");
		return;
	}
	my @dircontents = Slim::Utils::Misc::readDirectory($playlistDir,"sql");

	my %playLists = ();
	
	for my $item (@dircontents) {

		my $url = catfile($playlistDir, $item);

        open(my $fh, $url) or do {
                debugMsg("Couldn't open: $url : $!\n");
                next;
        };

		my $name = undef;
		my $statement = '';
        for my $line (<$fh>) {
            chomp $line;

            # skip and strip comments & empty lines
            $line =~ s/\s*--.*?$//o;
            $line =~ s/^\s*//o;

            next if $line =~ /^--/;
            next if $line =~ /^\s*$/;

			if(!$name) {
				$name = $line;
			}else {
				if($statement) {
					$statement .= "\n";
				}
				$statement .= $line;
			}
        }
        close $fh;
		
		if($name && $statement) {
			$playLists{$name} = $statement;
			my $tmp = $playLists{$name};
		}
	}
	return \%playLists;
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my @listRef = ();
	my $playLists = getPlayLists($client);
	foreach my $playlist (sort keys %$playLists) {
		push @listRef, $playlist;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_SQLPLAYLIST} {count}',
		listRef    => \@listRef,
		overlayRef => \&getOverlay,
		modeName   => 'SQLPLayList',
		onPlay     => sub {
			my ($client, $item) = @_;
			handlePlayOrAdd($client, $item, 0);		
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			handlePlayOrAdd($client, $item, 1);
		},
		onRight    => sub {
			my ($client, $item) = @_;
			$client->bumpRight();
		},
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub commandCallback {
	my ($client, $paramsRef) = @_;

	my $slimCommand = $paramsRef->[0];

	# we dont care about generic ir blasts
	return if $slimCommand eq 'ir';

	debugMsg("received command ".(join(' ', @$paramsRef))."\n");

	if (!defined $client || !defined $type{$client}) {

		if ($::d_plugins) {
			debugMsg("No client!\n");
			bt();
		}
		return;
	}
	
	debugMsg("while in mode: ".($type{$client}).", from ".($client->name)."\n");

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($slimCommand eq 'newsong'
		|| $slimCommand eq 'playlist' && $paramsRef->[1] eq 'delete' && $paramsRef->[2] > $songIndex) {

        if ($::d_plugins) {
			if ($slimCommand eq 'newsong') {
				debugMsg("new song detected ($songIndex)\n");
			} else {
				debugMsg("deletion detected ($paramsRef->[2]");
			}
		}
		
		my $songsToKeep = Slim::Utils::Prefs::get('plugin_sqlplaylist_number_of_old_tracks');
		if ($songIndex && $songsToKeep ne '') {
			debugMsg("Stripping off completed track(s)\n");

			Slim::Control::Command::clearExecuteCallback(\&commandCallback);
			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
				Slim::Control::Command::execute($client, ['playlist', 'delete', 0]);
			}
			Slim::Control::Command::setExecuteCallback(\&commandCallback);
		}

		playRandom($client, $type{$client}, 1);
	} elsif (($slimCommand eq 'playlist') && exists $stopcommands{$paramsRef->[1]}) {

		debugMsg("cyclic mode ending due to playlist: ".(join(' ', @$paramsRef))." command\n");
		playRandom($client, 'disable');
	}
}

sub initPlugin {
	# playlist commands that will stop random play
	%stopcommands = (
		'clear'		 => 1,
		'loadtracks' => 1, # multiple play
		'playtracks' => 1, # single play
		'load'		 => 1, # old style url load (no play)
		'play'		 => 1, # old style url play
		'loadalbum'	 => 1, # old style multi-item load
		'playalbum'	 => 1, # old style multi-item play
	);
	
	checkDefaults();
}

sub shutdownPlugin {
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
}

sub getFunctions {
	# Functions to allow mapping of mixes to keypresses
	return {
		'tracks' => sub {
			my $client = shift;
	
			playRandom($client, 'track');
		},
	
		'albums' => sub {
			my $client = shift;
	
			playRandom($client, 'album');
		},
	
		'artists' => sub {
			my $client = shift;
	
			playRandom($client, 'artist');
		},
		
		'year' => sub {
			my $client = shift;
	
			playRandom($client, 'year');
		},
	}
}

sub checkDefaults {
	my $prefVal = Slim::Utils::Prefs::get('plugin_sqlplaylist_number_of_tracks');
	if (! defined $prefVal || $prefVal !~ /^[0-9]+$/) {
		debugMsg("Defaulting plugin_sqlplaylist_number_of_tracks to 10\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_number_of_tracks', 10);
	}
	
	$prefVal = Slim::Utils::Prefs::get('plugin_sqlplaylist_number_of_old_tracks');
	if (! defined $prefVal || $prefVal !~ /^$|^[0-9]+$/) {
		# Default to keeping all tracks
		debugMsg("Defaulting plugin_sqlplaylist_number_of_old_tracks to ''\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_number_of_old_tracks', '');
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_sqlplaylist_playlist_directory');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_sqlplaylist_playlist_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_number_of_old_tracks', $dir);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_sqlplaylist_showmessages');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		debugMsg("Defaulting plugin_sqlplaylist_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_showmessages', 0);
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_sqlplaylist_playlist_directory','plugin_sqlplaylist_number_of_tracks','plugin_sqlplaylist_number_of_old_tracks','plugin_sqlplaylist_showmessages'],
	 GroupHead => string('PLUGIN_SQLPLAYLIST_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_SQLPLAYLIST_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_sqlplaylist_showmessages => {
			'validate'     => \&Slim::Web::Setup::validateTrueFalse
			,'PrefChoose'  => string('PLUGIN_SQLPLAYLIST_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_SQLPLAYLIST_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_sqlplaylist_showmessages"); }
		},		
	plugin_sqlplaylist_playlist_directory => {
			'validate' => \&Slim::Web::Setup::validateIsDir
			,'PrefChoose' => string('PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY')
			,'changeIntro' => string('PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory"); }
		},
	plugin_sqlplaylist_number_of_tracks => {
			'validate' => \&Slim::Web::Setup::validateInt
			,'PrefChoose' => string('PLUGIN_SQLPLAYLIST_NUMBER_OF_TRACKS')
			,'changeIntro' => string('PLUGIN_SQLPLAYLIST_NUMBER_OF_TRACKS')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_sqlplaylist_number_of_tracks"); }
		},
	plugin_sqlplaylist_number_of_old_tracks => {
			'validate' => \&Slim::Web::Setup::validateInt
			,'PrefChoose' => string('PLUGIN_SQLPLAYLIST_NUMBER_OF_OLD_TRACKS')
			,'changeIntro' => string('PLUGIN_SQLPLAYLIST_NUMBER_OF_OLD_TRACKS')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_sqlplaylist_number_of_old_tracks"); }
		}
	);
	return (\%setupGroup,\%setupPrefs);
}

sub getTracksForPlaylist {
	my $client = shift;
	my $type = shift;
	my $limit = shift;
	my $playLists = getPlayLists($client);
	my $sqlstatements = $playLists->{$type};
	my @result;
	my $trackno = 0;
	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
    for my $sql (split(/[\n\r]/,$sqlstatements)) {
		my $sth = $dbh->prepare( $sql );
		debugMsg("Executing: $sql\n");
		$sth->execute() or do {
            debugMsg("Error executing: $sql\n");
            $sql = undef;
		};

        if ($sql =~ /^SELECT+/oi) {
			debugMsg("Executing and collecting: $sql\n");
			my $url;
			$sth->bind_columns( undef, \$url);
			while( $sth->fetch() ) {
			  my $track = $ds->objectForUrl($url);
			  $trackno++;
			  if(!$limit || $trackno<=$limit) {
				debugMsg("Adding: ".($track->url)."\n");
			  	push @result, $track;
			  }
			}
		}
		$sth->finish();
	}

	
	return \@result;
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','SQLPlayList: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_sqlplaylist_showmessages"));
}

sub strings {
	return <<EOF;
PLUGIN_SQLPLAYLIST
	EN	SQL Playlist

PLUGIN_SQLPLAYLIST_DISABLED
	EN	SQL Playlist Stopped

PLUGIN_SQLPLAYLIST_CHOOSE_BELOW
	EN	Choose a random mix of music from your library:

PLUGIN_SQLPLAYLIST_BEFORE_NUM_TRACKS
	EN	Now Playing will show

PLUGIN_SQLPLAYLIST_AFTER_NUM_TRACKS
	EN	upcoming songs and

PLUGIN_SQLPLAYLIST_AFTER_NUM_OLD_TRACKS
	EN	recently played songs.

PLUGIN_SQLPLAYLIST_SETUP_GROUP
	EN	SQL PlayList

PLUGIN_SQLPLAYLIST_SETUP_GROUP_DESC
	EN	SQL PlayList is a smart playlist plugins based on SQL queries

PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY
	EN	Playlist directory

PLUGIN_SQLPLAYLIST_SHOW_MESSAGES
	EN	Show debug messages

PLUGIN_SQLPLAYLIST_NUMBER_OF_TRACKS
	EN	Number of tracks

PLUGIN_SQLPLAYLIST_NUMBER_OF_OLD_TRACKS
	EN	Number of old tracks

SETUP_PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY
	EN	Playlist directory

SETUP_PLUGIN_SQLPLAYLIST_SHOWMESSAGES
	EN	Debugging

SETUP_PLUGIN_SQLPLAYLIST_NUMBER_OF_TRACKS
	EN	Number of tracks

SETUP_PLUGIN_SQLPLAYLIST_NUMBER_OF_OLD_TRACKS
	EN	Number of old tracks

PLUGIN_SQLPLAYLIST_BEFORE_NUM_TRACKS
	EN	Now Playing will show

PLUGIN_SQLPLAYLIST_BEFORE_NUM_TRACKS
	EN	upcoming songs and

PLUGIN_SQLPLAYLIST_AFTER_NUM_OLD_TRACKS
	EN	recently played songs.

PLUGIN_SQLPLAYLIST_CHOOSE_BELOW
	EN	Choose a playlist with music from your library:

PLUGIN_SQLPLAYLIST_GENERAL_HELP
	EN	You can add or remove songs from your mix at any time. To stop a random mix, clear your playlist or click to

EOF

}

1;

__END__
