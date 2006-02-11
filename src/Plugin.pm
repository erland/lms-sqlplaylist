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
use Class::Struct;

my %stopcommands = ();
# Information on each clients sqlplaylist
my %mixInfo      = ();
my $htmlTemplate = 'plugins/SQLPlayList/sqlplaylist_list.html';
my $ds = Slim::Music::Info::getCurrentDataStore();
my $playLists = undef;
struct PlayListInfo => {
	id => '$',
	name => '$',
	sql => '$'
};

my $disable = PlayListInfo->new( id => 'disable', name => '', sql => '');
	
sub getDisplayName {
	return 'PLUGIN_SQLPLAYLIST';
}

# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $find, $limit, $addOnly) = @_;

	debugMsg("Starting random selection of $limit items for type: $type\n");
	
	my $playlist = getPlayList($client,$type);
	my $items = getTracksForPlaylist($client,$playlist,$limit);

	my $noOfItems = (scalar @$items);
	debugMsg("Find returned ".$noOfItems." items\n");
			
	# Pull the first track off to add / play it if needed.
	my $item = shift @{$items};

	if ($item && ref($item)) {
		my $string = $item->title;
		debugMsg("".($addOnly ? 'Adding ' : 'Playing ')."$type: $string, ".($item->id)."\n",

		# Replace the current playlist with the first item / track or add it to end
		my $request = $client->execute(['playlist', $addOnly ? 'addtracks' : 'loadtracks',
		                  sprintf('track=%d', $item->id)]));
		
		if ($::VERSION ge '6.5') {
			# indicate request source
			$request->source('PLUGIN_TRACKSTAT');
		}

		# Add the remaining items to the end
		if (! defined $limit || $limit > 1) {
			debugMsg("Adding ".(scalar @$items)." tracks to end of playlist\n");
			$client->execute(['playlist', 'addtracks', 'listRef', $items]);
			if ($::VERSION ge '6.5') {
				$request->source('PLUGIN_TRACKSTAT');
			}
		}
	} 
	return $noOfItems;
}


# Add random tracks to playlist if necessary
sub playRandom {
	# If addOnly, then track(s) are appended to end.  Otherwise, a new playlist is created.
	my ($client, $type, $addOnly) = @_;

	# disable this during the course of this function, since we don't want
	# to retrigger on commands we send from here.
	if ($::VERSION ge '6.5') {
	} else {
		Slim::Control::Command::clearExecuteCallback(\&commandCallback62);
	}

	debugMsg("playRandom called with type $type\n");
	
	# Whether to keep adding tracks after generating the initial playlist
	my $continuousMode = Slim::Utils::Prefs::get('plugin_sqlplaylist_keep_adding_tracks');;
	
	# If this is a new mix, store the start time
	my $startTime = undef;
	if ($continuousMode && $mixInfo{$client}->{'type'} ne $type) {
		$startTime = time();
	}

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;
	debugMsg("$songsRemaining songs remaining, songIndex = $songIndex\n");

	# Work out how many items need adding
	my $numItems = 0;

	if($type ne 'disable') {
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

	my $count = 0;
	if ($numItems) {
		unless ($addOnly) {
			$client->execute(['stop']);
			$client->execute(['power', '1']);
		}
		Slim::Player::Playlist::shuffle($client, 0);
		
		# String to show with showBriefly
		my $string = '';

		my $playlist = getPlayList($client,$type);
		if($playlist) {
			$string = $playlist->name;
		}

		# Strings for non-track modes could be long so need some time to scroll
		my $showTime = 5;
		
		# Add tracks 
		my $find;
		$count = findAndAdd($client,
                        $type,
                        $find,
                        $numItems,
			            # 2nd time round just add tracks to end
					    $addOnly);

		if($count>0) {
			# Do a show briefly the first time things are added, or every time a new album/artist/year
			# is added
			if (!$addOnly || $type ne $mixInfo{$client}->{'type'}) {
				# Don't do showBrieflys if visualiser screensavers are running as the display messes up
				if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
					$client->showBriefly(string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'),
										 $string, $showTime);
				}
			}

		}else {
				if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
					$client->showBriefly(string('PLUGIN_SQLPLAYLIST_NOW_PLAYING_FAILED'),
										 string('PLUGIN_SQLPLAYLIST_NOW_PLAYING_FAILED')." ".$string, $showTime);
				}
		}
		# Never show random as modified, since its a living playlist
		$client->currentPlaylistModified(0);		
	}
	
	if ($type eq 'disable') {
		if ($::VERSION ge '6.5') {
		}else {
			Slim::Control::Command::clearExecuteCallback(\&commandCallback62);
		}
		debugMsg("cyclic mode ended\n");
		# Don't do showBrieflys if visualiser screensavers are running as the display messes up
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
			$client->showBriefly(string('PLUGIN_SQLPLAYLIST'), string('PLUGIN_SQLPLAYLIST_DISABLED'));
		}
		$mixInfo{$client} = undef;
	} else {
		if ($::VERSION ge '6.5') {
		}else {
			Slim::Control::Command::setExecuteCallback(\&commandCallback62);
		}
		if(!$numItems || $numItems==0 || $count>0) {
			debugMsg("Playing ".($continuousMode ? 'continuous' : 'static')." $type with ".Slim::Player::Playlist::count($client)." items\n");
			# $startTime will only be defined if this is a new (or restarted) mix
			if (defined $startTime) {
				# Record current mix type and the time it was started.
				# Do this last to prevent menu items changing too soon
				debugMsg("New mix started at ".$startTime."\n", );
				$mixInfo{$client}->{'type'} = $type;
				$mixInfo{$client}->{'startTime'} = $startTime;
			}
		}else {
			$mixInfo{$client}->{'type'} = undef;
		}
	}
}

# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;

	my $id = undef;
	my $name = '';
	if($item) {
		$id = $item->id;
		$name = $item->name;
	}
	# if showing the current mode, show altered string
	if ($mixInfo{$client} && $id eq $mixInfo{$client}->{'type'}) {
		return string('PLUGIN_SQLPLAYLIST_PLAYING')." ".$name;
		
	# if a mode is active, handle the temporarily added disable option
	} elsif ($id eq 'disable' && $mixInfo{$client}) {
		return string('PLUGIN_SQLPLAYLIST_PRESS_RIGHT');
	} else {
		return $name;
	}
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	# Put the right arrow by genre filter and notesymbol by mixes
	if ($item->id eq 'disable') {
		return [undef, Slim::Display::Display::symbol('rightarrow')];
	}elsif (!$mixInfo{$client} || $item->id ne $mixInfo{$client}->{'type'}) {
		return [undef, Slim::Display::Display::symbol('notesymbol')];
	} else {
		return [undef, undef];
	}
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	debugMsg("".($add ? 'Add' : 'Play')."$item\n");
	
	# reconstruct the list of options, adding and removing the 'disable' option where applicable
	my $listRef = Slim::Buttons::Common::param($client, 'listRef');
		
	if ($item eq 'disable') {
		pop @$listRef;
		
	# only add disable option if starting a mode from idle state
	} elsif (! $mixInfo{$client}) {
		push @$listRef, $disable;
	}
	Slim::Buttons::Common::param($client, 'listRef', $listRef);

	# Clear any current mix type in case user is restarting an already playing mix
	$mixInfo{$client} = undef;

	# Go go go!
	playRandom($client, $item, $add);
}

sub getPlayList {
	my $client = shift;
	my $type = shift;
	
	return undef unless $type;

	debugMsg("Get playlist: $type\n");
	if(!$playLists) {
		$playLists = getPlayLists($client);
	}
	return undef unless $playLists;
	
	return $playLists->{$type};
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

			# use "--PlaylistName:" as name of playlist
			$line =~ s/^-- *PlaylistName *[:=] *//io;
			
            # skip and strip comments & empty lines
            $line =~ s/\s*--.*?$//o;
            $line =~ s/^\s*//o;

            next if $line =~ /^--/;
            next if $line =~ /^\s*$/;

			if(!$name) {
				$name = $line;
			}else {
				$line =~ s/\s+$//;
				if($statement) {
					if( $statement =~ /;$/ ) {
						$statement .= "\n";
					}else {
						$statement .= " ";
					}
				}
				$statement .= $line;
			}
        }
        close $fh;
		
		if($name && $statement) {
			debugMsg("Got playlist: $name\n");
			$playLists{escape($name,"^A-Za-z0-9\-_")} = PlayListInfo->new( id => escape($name,"^A-Za-z0-9\-_"), name => $name, sql => $statement );
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
	$playLists = getPlayLists($client);
	foreach my $playlist (sort keys %$playLists) {
		push @listRef, $playLists->{$playlist};
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_SQLPLAYLIST} {count}',
		listRef    => \@listRef,
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'SQLPLayList',
		onPlay     => sub {
			my ($client, $item) = @_;
			handlePlayOrAdd($client, $item->id, 0);		
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			handlePlayOrAdd($client, $item->id, 1);
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if($item->id eq 'disable') {
				handlePlayOrAdd($client, $item->id, 0);
			}else {
				$client->bumpRight();
			}
		},
	);

	# if we have an active mode, temporarily add the disable option to the list.
	if ($mixInfo{$client}) {
		push @{$params{listRef}},$disable;
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub commandCallback62 {
	my ($client, $paramsRef) = @_;

	my $slimCommand = $paramsRef->[0];

	# we dont care about generic ir blasts
	return if $slimCommand eq 'ir';

	debugMsg("received command ".(join(' ', @$paramsRef))."\n");

	if (!defined $client || !defined $mixInfo{$client}->{'type'}) {

		if ($::d_plugins) {
			debugMsg("No client!\n");
		}
		return;
	}
	
	debugMsg("while in mode: ".($mixInfo{$client}->{'type'}).", from ".($client->name)."\n");

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

			Slim::Control::Command::clearExecuteCallback(\&commandCallback62);
			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
				Slim::Control::Command::execute($client, ['playlist', 'delete', 0]);
			}
			Slim::Control::Command::setExecuteCallback(\&commandCallback62);
		}

		playRandom($client, $mixInfo{$client}->{'type'}, 1);
	} elsif (($slimCommand eq 'playlist') && exists $stopcommands{$paramsRef->[1]}) {

		debugMsg("cyclic mode ending due to playlist: ".(join(' ', @$paramsRef))." command\n");
		playRandom($client, 'disable');
	}
}

sub commandCallback65 {
	my $request = shift;
	
	my $client = $request->client();

	if ($request->source() eq 'PLUGIN_TRACKSTAT') {
		return;
	}

	debugMsg("received command ".($request->getRequestString())."\n");

	# because of the filter this should never happen
	# in addition there are valid commands (rescan f.e.) that have no
	# client so the bt() is strange here
	if (!defined $client || !defined $mixInfo{$client}->{'type'}) {

		if ($::d_plugins) {
			debugMsg("No client!\n");
			bt();
		}
		return;
	}
	
	debugMsg("while in mode: ".($mixInfo{$client}->{'type'}).", from ".($client->name)."\n");

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($request->isCommand([['playlist'], ['newsong']])
		|| $request->isCommand([['playlist'], ['delete']]) && $request->getParam('_index') > $songIndex) {

        if ($::d_plugins) {
			if ($request->isCommand([['playlist'], ['newsong']])) {
				debugMsg("new song detected ($songIndex)\n");
			} else {
				debugMsg("deletion detected (".($request->getParam('_index')).")\n");
			}
		}
		
		my $songsToKeep = Slim::Utils::Prefs::get('plugin_sqlplaylist_number_of_old_tracks');
		if ($songIndex && $songsToKeep ne '') {
			debugMsg("Stripping off completed track(s)\n");

			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
				my $request = $client->execute(['playlist', 'delete', 0]);
				$request->source('PLUGIN_TRACKSTAT');
			}
		}

		playRandom($client, $mixInfo{$client}->{'type'}, 1);
	} elsif ($request->isCommand([['playlist'], [keys %stopcommands]])) {

		debugMsg("cyclic mode ending due to playlist: ".($request->getRequestString())." command\n");
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

	if ($::VERSION ge '6.5') {
		# set up our subscription
		Slim::Control::Request::subscribe(\&commandCallback65, 
			[['playlist'], ['newsong', 'delete', keys %stopcommands]]);
	}
}

sub shutdownPlugin {
	if ($::VERSION ge '6.5') {
		Slim::Control::Request::unsubscribe(\&commandCallback65);
	}else {
		Slim::Control::Command::clearExecuteCallback(\&commandCallback62);
	}
}

sub webPages {

	my %pages = (
		"sqlplaylist_list\.(?:htm|xml)"     => \&handleWebList,
		"sqlplaylist_mix\.(?:htm|xml)"      => \&handleWebMix,
		"sqlplaylist_settings\.(?:htm|xml)" => \&handleWebSettings,
	);

	my $value = $htmlTemplate;

	if (grep { /^SQLPlayList::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	} 

	#Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_SQLPLAYLIST' => $value });

	return (\%pages,$value);
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	$playLists = getPlayLists($client);
	my $playlist = getPlayList($client,$mixInfo{$client}->{'type'});
	my $name = undef;
	if($playlist) {
		$name = $playlist->name;
	}
	$params->{'pluginSQLPlayListPlayLists'} = $playLists;
	$params->{'pluginSQLPlayListNumTracks'} = Slim::Utils::Prefs::get('plugin_sqlplaylist_number_of_tracks');
	$params->{'pluginSQLPlayListNumOldTracks'} = Slim::Utils::Prefs::get('plugin_sqlplaylist_number_of_old_tracks');
	$params->{'pluginSQLPlayListContinuousMode'} = Slim::Utils::Prefs::get('plugin_sqlplaylist_keep_adding_tracks');
	$params->{'pluginSQLPlayListNowPlaying'} = $name;
	$params->{'pluginSQLPlayListVersion'} = $::VERSION;
	
	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

# Handles play requests from plugin's web page
sub handleWebMix {
	my ($client, $params) = @_;
	if (defined $client && $params->{'type'}) {
		playRandom($client, $params->{'type'}, $params->{'addOnly'});
	}
	handleWebList($client, $params);
}

# Handles settings changes from plugin's web page
sub handleWebSettings {
	my ($client, $params) = @_;

	if ($params->{'numTracks'} =~ /^[0-9]+$/) {
		Slim::Utils::Prefs::set('plugin_sqlplaylist_number_of_tracks', $params->{'numTracks'});
	} else {
		debugMsg("Invalid value for numTracks\n");
	}
	if ($params->{'numOldTracks'} eq '' || $params->{'numOldTracks'} =~ /^[0-9]+$/) {
		Slim::Utils::Prefs::set('plugin_sqlplaylist_number_of_old_tracks', $params->{'numOldTracks'});	
	} else {
		debugMsg("Invalid value for numOldTracks\n");
	}
	Slim::Utils::Prefs::set('plugin_sqlplaylist_keep_adding_tracks', $params->{'continuousMode'} ? 1 : 0);

	# Pass on to check if the user requested a new mix as well
	handleWebMix($client, $params);
}

sub getFunctions {
	# Functions to allow mapping of mixes to keypresses
	return {
		'up' => sub  {
			my $client = shift;
			$client->bumpUp();
		},
		'down' => sub  {
			my $client = shift;
			$client->bumpDown();
		},
		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		'right' => sub  {
			my $client = shift;
			$client->bumpRight();
		}
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

	if (! defined Slim::Utils::Prefs::get('plugin_sqlplaylist_keep_adding_tracks')) {
		# Default to continous mode
		debugMsg("Defaulting plugin_sqlplaylist_keep_adding_tracks to 1\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_keep_adding_tracks', 1);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_sqlplaylist_playlist_directory');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_sqlplaylist_playlist_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_playlist_directory', $dir);
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
	my $playlist = shift;
	my $limit = shift;
	my $sqlstatements = $playlist->sql;
	my @result;
	my $trackno = 0;
	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
    for my $sql (split(/[\n\r]/,$sqlstatements)) {
    	eval {
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
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}		
	}

	
	return \@result;
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
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

PLUGIN_SQLPLAYLIST_AFTER_NUM_TRACKS
	EN	upcoming songs and

PLUGIN_SQLPLAYLIST_AFTER_NUM_OLD_TRACKS
	EN	recently played songs.

PLUGIN_SQLPLAYLIST_CHOOSE_BELOW
	EN	Choose a playlist with music from your library:

PLUGIN_SQLPLAYLIST_PLAYING
	EN	Playing

PLUGIN_SQLPLAYLIST_PRESS_RIGHT
	EN	Press RIGHT to stop adding songs

PLUGIN_SQLPLAYLIST_GENERAL_HELP
	EN	You can add or remove songs from your mix at any time. To stop adding songs, clear your playlist or click to

PLUGIN_SQLPLAYLIST_DISABLE
	EN	Stop adding songs

PLUGIN_SQLPLAYLIST_CONTINUOUS_MODE
	EN	Add new items when old ones finish

PLUGIN_SQLPLAYLIST_NOW_PLAYING_FAILED
	EN	Failed 

EOF

}

1;

__END__
