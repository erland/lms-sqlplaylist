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
my $sqlerrors = '';
struct PlayListInfo => {
	id => '$',
	file => '$',
	name => '$',
	sql => '$',
	fulltext => '$'
};

my $disable = PlayListInfo->new( id => 'disable', file => '', name => '', sql => '', fulltext => '');
	
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
			$request->source('PLUGIN_DYNAMICPLAYLIST');
		}

		# Add the remaining items to the end
		if (! defined $limit || $limit > 1) {
			debugMsg("Adding ".(scalar @$items)." tracks to end of playlist\n");
			$client->execute(['playlist', 'addtracks', 'listRef', $items]);
			if ($::VERSION ge '6.5') {
				$request->source('PLUGIN_DYNAMICPLAYLIST');
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
		my $fulltext = '';
        for my $line (<$fh>) {
        	if($name) {
        		$fulltext .= $line;
        	}
            chomp $line;

			# use "--PlaylistName:" as name of playlist
			$line =~ s/^\s*--\s*PlaylistName\s*[:=]\s*//io;
			
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
			$playLists{escape($name,"^A-Za-z0-9\-_")} = PlayListInfo->new( id => escape($name,"^A-Za-z0-9\-_"), file => $item, name => $name, sql => Slim::Utils::Unicode::utf8decode($statement,'utf8') , fulltext => Slim::Utils::Unicode::utf8decode($fulltext,'utf8'));
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

	if ($request->source() eq 'PLUGIN_DYNAMICPLAYLIST') {
		return;
	}

	debugMsg("received command ".($request->getRequestString())."\n");

	# because of the filter this should never happen
	# in addition there are valid commands (rescan f.e.) that have no
	# client so the bt() is strange here
	if (!defined $client || !defined $mixInfo{$client}->{'type'}) {

		if ($::d_plugins) {
			debugMsg("No client!\n");
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
				$request->source('PLUGIN_DYNAMICPLAYLIST');
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
		"sqlplaylist_editplaylist\.(?:htm|xml)"      => \&handleWebEditPlaylist,
		"sqlplaylist_newplaylist\.(?:htm|xml)"      => \&handleWebNewPlaylist,
		"sqlplaylist_saveplaylist\.(?:htm|xml)"      => \&handleWebSavePlaylist,
		"sqlplaylist_savenewplaylist\.(?:htm|xml)"      => \&handleWebSaveNewPlaylist,
		"sqlplaylist_removeplaylist\.(?:htm|xml)"      => \&handleWebRemovePlaylist,
		"sqlplaylist_generatenewplaylist\.(?:htm|xml)"      => \&handleWebGenerateNewPlaylist,
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

# Draws the plugin's edit playlist web page
sub handleWebEditPlaylist {
	my ($client, $params) = @_;

	if ($params->{'type'}) {
		my $playlist = getPlayList($client,$params->{'type'});
		if($playlist) {
			$params->{'pluginSQLPlayListEditPlayListFile'} = escape($playlist->file);
			$params->{'pluginSQLPlayListEditPlayListName'} = $playlist->name;
			$params->{'pluginSQLPlayListEditPlayListText'} = Slim::Utils::Unicode::utf8decode($playlist->fulltext,'utf8');
			$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($params->{'pluginSQLPlayListEditPlayListFile'});
		}else {
			warn "Cannot find: ".$params->{'type'};
		}
	}

	$params->{'pluginSQLPlayListError'} = undef;
	$params->{'pluginSQLPlayListVersion'} = $::VERSION;
	
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editplaylist.html', $params);
}

# Draws the plugin's edit playlist web page
sub handleWebTestNewPlaylist {
	my ($client, $params) = @_;

	handleWebTestPlaylist($client,$params);
	
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newplaylist.html', $params);
}

# Draws the plugin's edit playlist web page
sub handleWebTestEditPlaylist {
	my ($client, $params) = @_;

	handleWebTestPlaylist($client,$params);
	
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editplaylist.html', $params);
}

sub handleWebTestPlaylist {
	my ($client, $params) = @_;
	$params->{'pluginSQLPlayListEditPlayListFile'} = $params->{'file'};
	$params->{'pluginSQLPlayListEditPlayListName'} = $params->{'name'};
	$params->{'pluginSQLPlayListEditPlayListText'} = $params->{'text'};
	$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($params->{'file'});
	my $ds = Slim::Music::Info::getCurrentDataStore();
	if($params->{'text'}) {
		my $sql = createSQL(Slim::Utils::Unicode::utf8decode($params->{'text'},'utf8'));
		if($sql) {
			my $tracks = executeSQLForPlaylist($sql);
			my @resultTracks;
			my $itemNumber = 0;
			foreach my $track (@$tracks) {
			  	my %trackInfo = ();
				my $fieldInfo = Slim::DataStores::Base->fieldInfo;
	            my $levelInfo = $fieldInfo->{'track'};
				
	            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $track);
			  	$trackInfo{'title'} = Slim::Music::Info::standardTitle(undef,$track);
			  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
	            $trackInfo{'itemobj'}          = $track;
			  	push @resultTracks,\%trackInfo;
			}
			if(defined(@resultTracks) && scalar(@resultTracks)>0) {
				$params->{'pluginSQLPlayListEditPlayListTestResult'} = \@resultTracks;
			}
		}
	}

	if($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginSQLPlayListError'} = $sqlerrors;
	}else {
		$params->{'pluginSQLPlayListError'} = undef;
	}
	$params->{'pluginSQLPlayListVersion'} = $::VERSION;
}

# Returns a hash whose keys are the genres in the db
sub getGenres {
	my ($client) = @_;

	# Should use genre.name in following find, but a bug in find() doesn't allow this	
   	my $items = $ds->find({
		'field'  => 'genre',
		'cache'  => 0,
	});
	
	# Extract each genre name into a hash
	my %clientGenres = ();
	foreach my $item (@$items) {
		$clientGenres{$item->{'name'}} = {
		                                 # Put the name here as well so the hash can be passed to
		                                 # INPUT.Choice as part of listRef later on
		                                 name    => $item->{'name'},
		                                 id      => $item->{'id'},
		                                 enabled => 0,
									 };
	}

	return %clientGenres;
}

sub getArtists {
	my ($client) =@_;
	
	my $items = $ds->find({
		'field'  => 'artist',
		'sortBy' => 'name',
		'cache'  => 0,
	});
	
	my %clientArtists = ();
	for my $item (@$items) {
		$clientArtists{escape($item->{'name'})} = {
			name => $item->{'name'},
			id => $item->{'id'},
		};
	}
	
	return %clientArtists;
}

# Draws the plugin's edit playlist web page
sub handleWebNewPlaylist {
	my ($client, $params) = @_;

	foreach my $param (keys %$params) {
		debugMsg("Got: $param = ".$params->{$param}."\n");
	}

	$params->{'pluginSQLPlayListError'} = undef;
	$params->{'pluginSQLPlayListVersion'} = $::VERSION;
	$params->{'pluginSQLPlayListGenreList'} = {getGenres($client)};
	$params->{'pluginSQLPlayListArtistList'} = {getArtists($client)};
	
	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    if($driver eq 'mysql') {
		$params->{'pluginSQLPlayListDatabase'} = "mysql";
    }else {
		$params->{'pluginSQLPlayListDatabase'} = "sqlite";
    }

	my $trackStat;
	if ($::VERSION ge '6.5') {
		$trackStat = Slim::Utils::PluginManager::enabledPlugin("TrackStat",$client);
	}else {
		$trackStat = grep(/TrackStat/,Slim::Buttons::Plugins::enabledPlugins($client));
    }
	if($trackStat) {
		$params->{'pluginSQLPlayListTrackStat'} = 1;
	}
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_templatenewplaylist.html', $params);
}

# Draws the plugin's edit playlist web page
sub handleWebGenerateNewPlaylist {
	my ($client, $params) = @_;

	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }

	$params->{'pluginSQLPlayListError'} = undef;
	$params->{'pluginSQLPlayListVersion'} = $::VERSION;
	my $genreListString = Slim::Utils::Unicode::utf8decode(getGenreListString($client,$params),'utf8');
	my $artistListString = Slim::Utils::Unicode::utf8decode(getArtistListString($client,$params),'utf8');
	debugMsg("Genres = ".$genreListString."\n");
	debugMsg("Artists = ".$artistListString."\n");
	if($params->{'type'} eq "random") {
		$params->{'pluginSQLPlayListEditPlayListText'} = "select url from tracks order by $orderBy limit 10;";
	}elsif($params->{'type'} eq "includinggenres") {
		my $sql = "select url from tracks,genre_track,genres \n\twhere tracks.id=genre_track.track and \n\t\tgenre_track.genre=genres.id and\n\t\ttracks.audio=1";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenres.name in (";
			$sql .= $genreListString;
			$sql .= ")";
		}
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "includinggenresincludingartists") {
		my $sql = "select url from tracks,genre_track,genres,contributor_track,contributors \n\twhere tracks.id=genre_track.track and \n\t\tgenre_track.genre=genres.id and \n\t\ttracks.id=contributor_track.track and \n\t\tcontributor_track.contributor=contributors.id and\n\t\ttracks.audio=1";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenres.name in (";
			$sql .= $genreListString;
			$sql .= ")";
		}
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributors.name in (";
			$sql .= $artistListString;
			$sql .= ")";
		}
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "includingartists") {
		my $sql = "select url from tracks,contributor_track,contributors \n\twhere tracks.id=contributor_track.track and \n\t\tcontributor_track.contributor=contributors.id and\n\t\ttracks.audio=1";
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributors.name in (";
			$sql .= $artistListString;
			$sql .= ")";
		}
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedincludinggenres") {
		my $sql = "select tracks.url from tracks,genre_track,genres,track_statistics \n\twhere tracks.id=genre_track.track and \n\t\tgenre_track.genre=genres.id and\n\t\ttracks.url=track_statistics.url and\n\t\ttrack_statistics.rating>=80 and\n\t\ttracks.audio=1";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenres.name in (";
			$sql .= $genreListString;
			$sql .= ")";
		}
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedincludingartists") {
		my $sql = "select tracks.url from tracks,contributor_track,contributors,track_statistics \n\twhere tracks.id=contributor_track.track and \n\t\tcontributor_track.contributor=contributors.id and\n\t\ttracks.url=track_statistics.url and\n\t\ttrack_statistics.rating>=80 and\n\t\ttracks.audio=1";
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributors.name in (";
			$sql .= $artistListString;
			$sql .= ")";
		}
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedincludinggenresincludingartists") {
		my $sql = "select tracks.url from tracks,genre_track,genres,contributor_track,contributors,track_statistics \n\twhere tracks.id=genre_track.track and \n\t\tgenre_track.genre=genres.id and \n\ttracks.id=contributor_track.track and \n\t\tcontributor_track.contributor=contributors.id and\n\t\ttracks.url=track_statistics.url and\n\t\ttrack_statistics.rating>=80 and\n\t\ttracks.audio=1";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenres.name in (";
			$sql .= $genreListString;
			$sql .= ")";
		}
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributors.name in (";
			$sql .= $artistListString;
			$sql .= ")";
		}
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenres") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "select distinct tracks.url from tracks \n\tleft join genre_track_withname on \n\t\ttracks.id=genre_track_withname.track";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenre_track_withname.name in(";
			$sql .= $genreListString;
			$sql .= ")"
		}
		$sql .= "\n\twhere ";
		if($genreListString ne "") {
			$sql .= "genre_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1 \n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludingartists") {
		my $sql = "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks \n\tleft join contributor_track_withname on \n\t\ttracks.id=contributor_track_withname.track";
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributor_track_withname.name in(";
			$sql .= $artistListString;
			$sql .= ")"
		}
		$sql .= "\n\twhere ";
		if($artistListString ne "") {
			$sql .= "contributor_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1 \n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenresexcludingartists") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks \n\tleft join genre_track_withname on \n\t\ttracks.id=genre_track_withname.track";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenre_track_withname.name in(";
			$sql .= $genreListString;
			$sql .= ")"
		}
		$sql .= "\n\tleft join contributor_track_withname on \n\t\ttracks.id=contributor_track_withname.track";
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributor_track_withname.name in(";
			$sql .= $artistListString;
			$sql .= ")"
		}
		$sql .= "\n\twhere ";
		if($genreListString ne "") {
			$sql .= "genre_track_withname.track is null and ";
		}
		if($artistListString ne "") {
			$sql .= "contributor_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1 \n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenressqlite") {
		my $sql = "select tracks.url from tracks";
		$sql .= "\n\twhere ";
		if($genreListString ne "") {
			$sql .= "\n\t\tnot exists (select * from genre_track,genres where";
			$sql .= "\n\t\t\tgenre=id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $genreListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1\n\t\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
		$sql .= "\n\twhere ";
		if($artistListString ne "") {
			$sql .= "\n\t\tnot exists (select * from contributor_track,contributors where";
			$sql .= "\n\t\t\tcontributor=id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $artistListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1\n\t\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenresexcludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
		$sql .= "\n\twhere ";
		if($genreListString ne "") {
			$sql .= "\n\t\tnot exists (select * from genre_track,genres where";
			$sql .= "\n\t\t\tgenre=id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $genreListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		if($artistListString ne "") {
			$sql .= "\n\t\tnot exists (select * from contributor_track,contributors where";
			$sql .= "\n\t\t\tcontributor=id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $artistListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1\n\t\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenres") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "select distinct tracks.url from tracks \n\tleft join genre_track_withname on \n\t\ttracks.id=genre_track_withname.track";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenre_track_withname.name in(";
			$sql .= $genreListString;
			$sql .= ")"
		}
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		$sql .= "\n\twhere ";
		if($genreListString ne "") {
			$sql .= "genre_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludingartists") {
		my $sql = "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks \n\tleft join contributor_track_withname on \n\t\ttracks.id=contributor_track_withname.track";
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributor_track_withname.name in(";
			$sql .= $artistListString;
			$sql .= ")"
		}
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		$sql .= "\n\twhere ";
		if($artistListString ne "") {
			$sql .= "contributor_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenresexcludingartists") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks \n\tleft join genre_track_withname on \n\t\ttracks.id=genre_track_withname.track";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenre_track_withname.name in(";
			$sql .= $genreListString;
			$sql .= ")"
		}
		$sql .= "\n\tleft join contributor_track_withname on \n\t\ttracks.id=contributor_track_withname.track";
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributor_track_withname.name in(";
			$sql .= $artistListString;
			$sql .= ")"
		}
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		$sql .= "\n\twhere ";
		if($genreListString ne "") {
			$sql .= "genre_track_withname.track is null and ";
		}
		if($artistListString ne "") {
			$sql .= "contributor_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenressqlite") {
		my $sql = "select tracks.url from tracks";
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		$sql .= "\n\twhere ";
		if($genreListString ne "") {
			$sql .= "\n\t\tnot exists (select * from genre_track,genres where";
			$sql .= "\n\t\t\tgenre=id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $genreListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80\n\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		$sql .= "\n\twhere ";
		if($artistListString ne "") {
			$sql .= "\n\t\tnot exists (select * from contributor_track,contributors where";
			$sql .= "\n\t\t\tcontributor=id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $artistListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80\n\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenresexcludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		$sql .= "\n\twhere ";
		if($genreListString ne "") {
			$sql .= "\n\t\tnot exists (select * from genre_track,genres where";
			$sql .= "\n\t\t\tgenre=id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $genreListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		if($artistListString ne "") {
			$sql .= "\n\t\tnot exists (select * from contributor_track,contributors where";
			$sql .= "\n\t\t\tcontributor=id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $artistListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80\n\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "toprated") {
		my $sql = "select tracks.url from tracks,track_statistics\n\t";
		$sql .= "where tracks.url = track_statistics.url and\n\t\t";
		$sql .= "track_statistics.rating>=80\n\t";
		$sql .= "order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}
		
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newplaylist.html', $params);
}

sub getGenreListString {
	my ($client,$params) = @_;
	
	my %genres = getGenres($client);
	my $first = 1;
	my $sql = '';
	foreach my $genre (keys %genres) {
		my $genreid = "genre_".$genres{$genre}{'id'};
		if($params->{$genreid}) {
			if(!$first) {
				$sql .= ","
			}
			$first = undef;
			$sql .= "'".$genres{$genre}{'name'}."'";
		}
	}
	return $sql;
}	

sub getArtistListString {
	my ($client,$params) = @_;
	
	
	my %artists = getArtists($client);
	my %selectedArtists;
	my $query = $params->{url_query};
	debugMsg("url_query = $query\n");
	if($query) {
        foreach my $param (split /\&/, $query) {
            if ($param =~ /([^=]+)=(.*)/) {
                my $name  = unescape($1);
                my $value = unescape($2);
                debugMsg("Got $name=$value\n");
                if($name eq 'artistList') {
                    # We need to turn perl's internal
                    # representation of the unescaped
                    # UTF-8 string into a "real" UTF-8
                    # string with the appropriate magic set.
                    if ($value ne '*' && $value ne '') {

                            $value = Slim::Utils::Unicode::utf8on($value);
                            $value = Slim::Utils::Unicode::utf8encode_locale($value);
                    }

					debugMsg("Adding $value\n");
                    $selectedArtists{$value}=$value;
                }
            }
        }
	}
	my $first = 1;
	my $sql = '';
	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	foreach my $artist (keys %artists) {
		my $artistid = $artists{$artist}{'id'};
		if($selectedArtists{$artistid}) {
			if(!$first) {
				$sql .= ","
			}
			$first = undef;
			$sql .= $dbh->quote($artists{$artist}{'name'});
		}
	}
	return $sql;
}	

# Draws the plugin's edit playlist web page
sub handleWebSavePlaylist {
	my ($client, $params) = @_;

	$params->{'pluginSQLPlayListError'} = undef;

	if($params->{'testonly'} eq "1") {
		return handleWebTestEditPlaylist($client,$params);
	}

	handleWebTestPlaylist($client,$params);
	
	if (!$params->{'text'} || !$params->{'file'} || !$params->{'name'}) {
		$params->{'pluginSQLPlayListError'} = 'All fields are mandatory';
	}

	my $playlistDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
	
	if (!defined $playlistDir || !-d $playlistDir) {
		$params->{'pluginSQLPlayListError'} = 'No playlist dir defined';
	}
	my $url = catfile($playlistDir, unescape($params->{'file'}));
	if (!-e $url) {
		$params->{'pluginSQLPlayListError'} = 'File already exist';
	}
	
	my $playlist = getPlayList($client,escape($params->{'name'},"^A-Za-z0-9\-_"));
	if($playlist && $playlist->file ne unescape($params->{'file'})) {
		$params->{'pluginSQLPlayListError'} = 'Playlist with that name already exists';
	}
	if(!savePlaylist($client,$params,$url)) {
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editplaylist.html', $params);
	}else {
		return handleWebList($client,$params)
	}

}

# Draws the plugin's edit playlist web page
sub handleWebSaveNewPlaylist {
	my ($client, $params) = @_;

	$params->{'pluginSQLPlayListError'} = undef;
	
	if($params->{'testonly'} eq "1") {
		return handleWebTestNewPlaylist($client,$params);
	}

	handleWebTestPlaylist($client,$params);
	
	if (!$params->{'text'} || !$params->{'file'} || !$params->{'name'}) {
		$params->{'pluginSQLPlayListError'} = 'All fields are mandatory';
	}

	my $playlistDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
	
	if (!defined $playlistDir || !-d $playlistDir) {
		$params->{'pluginSQLPlayListError'} = 'No playlist dir defined';
	}
	debugMsg("Got file: ".$params->{'file'}."\n");
	if($params->{'file'} !~ /.*\.sql$/) {
		$params->{'pluginSQLPlayListError'} = 'File name must end with .sql';
	}
	
	if($params->{'file'} !~ /^[0-9A-Za-z\._\- ]*$/) {
		$params->{'pluginSQLPlayListError'} = 'File name is only allowed to contain characters a-z , A-Z , 0-9 , - , _ , . , and space';
	}

	my $url = catfile($playlistDir, unescape($params->{'file'}));
	if (-e $url) {
		$params->{'pluginSQLPlayListError'} = 'File already exist';
	}
	my $playlist = getPlayList($client,escape($params->{'name'},"^A-Za-z0-9\-_"));
	if($playlist) {
		$params->{'pluginSQLPlayListError'} = 'Playlist with that name already exists';
	}

	if(!savePlaylist($client,$params,$url)) {
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newplaylist.html', $params);
	}else {
		return handleWebList($client,$params)
	}

}

sub handleWebRemovePlaylist {
	my ($client, $params) = @_;

	if ($params->{'type'}) {
		my $playlist = getPlayList($client,$params->{'type'});
		if($playlist) {
			my $playlistDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
			
			if (!defined $playlistDir || !-d $playlistDir) {
				warn "No playlist dir defined\n"
			}else {
				debugMsg("Deleteing playlist: ".$playlist->file."\n");
				my $url = catfile($playlistDir, unescape($playlist->file));
				unlink($url) or do {
					warn "Unable to delete file: ".$url.": $! \n";
				}
			}
		}else {
			warn "Cannot find: ".$params->{'type'}."\n";
		}
	}

	return handleWebList($client,$params)
}

sub savePlaylist 
{
	my ($client, $params, $url) = @_;
	my $fh;
	if(!($params->{'pluginSQLPlayListError'})) {
		debugMsg("Opening playlist file: $url\n");
	    open($fh,"> $url") or do {
	            $params->{'pluginSQLPlayListError'} = 'Error saving playlist';
	    };
	}
	if(!($params->{'pluginSQLPlayListError'})) {

		debugMsg("Writing to file: $url\n");
		print $fh "-- PlaylistName: ".$params->{'name'}."\n";
		print $fh $params->{'text'};
		debugMsg("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginSQLPlayListError'}) {
		$params->{'pluginSQLPlayListEditPlayListFile'} = $params->{'file'};
		$params->{'pluginSQLPlayListEditPlayListText'} = $params->{'text'};
		$params->{'pluginSQLPlayListEditPlayListName'} = $params->{'name'};
		$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($params->{'pluginSQLPlayListEditPlayListFile'});
		return undef;
	}else {
		return 1;
	}
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
			'validate' => \&validateIntOrEmpty
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
	@result = executeSQLForPlaylist($sqlstatements,$limit);
	
	return \@result;
}

sub createSQL {
	my $sqlstatements = shift;
	my $sql = '';
    for my $line (split(/[\n\r]/,$sqlstatements)) {
        chomp $line;

        # skip and strip comments & empty lines
        $line =~ s/\s*--.*?$//o;
        $line =~ s/^\s*//o;

        next if $line =~ /^--/;
        next if $line =~ /^\s*$/;

		$line =~ s/\s+$//;
		if($sql) {
			if( $sql =~ /;$/ ) {
				$sql .= "\n";
			}else {
				$sql .= " ";
			}
		}
		$sql .= $line;
    }
    return $sql;
}
sub executeSQLForPlaylist {
	my $sqlstatements = shift;
	my $limit = shift;
	my @result;
	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	my $trackno = 0;
	$sqlerrors = "";
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
			$sqlerrors .= $DBI::errstr."<br>";
		    warn "Database error: $DBI::errstr\n";
		}		
	}
	return \@result;
}
sub getDynamicPlayLists {
	my ($client) = @_;

	my $playLists = getPlayLists($client);
	
	my %result = ();
	
	foreach my $playlist (sort keys %$playLists) {
		my $playlistid = "sqlplaylist_".$playlist;
		my $current = $playLists->{$playlist};
		my %currentResult = (
			'id' => $playlist,
			'name' => $current->name
		);
		$result{$playlistid} = \%currentResult;
	}
	
	return \%result;
}

sub getNextDynamicPlayListTracks {
	my ($client,$dynamicplaylist,$limit) = @_;
	
	debugMsg("Getting tracks for: ".$dynamicplaylist->{'id'}."\n");
	my $playlist = getPlayList($client,$dynamicplaylist->{'id'});
	my $result = getTracksForPlaylist($client,$playlist,$limit);
	
	return \@{$result};
}
sub validateIntOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '' || $arg =~ /^\d+$/) {
		return $arg;
	}
	return undef;
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

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST
	EN	Edit

PLUGIN_SQLPLAYLIST_NEW_PLAYLIST
	EN	Create new playlist

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST_QUERY
	EN	SQL Query

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST_NAME
	EN	Playlist Name

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST_FILENAME
	EN	Filename

PLUGIN_SQLPLAYLIST_REMOVE_PLAYLIST
	EN	Delete

PLUGIN_SQLPLAYLIST_REMOVE_PLAYLIST_QUESTION
	EN	Are you sure you want to delete this playlist ?

PLUGIN_SQLPLAYLIST_TEMPLATE_GENRES_TITLE
	EN	Genres

PLUGIN_SQLPLAYLIST_TEMPLATE_GENRES_SELECT_NONE
	EN	No Genres

PLUGIN_SQLPLAYLIST_TEMPLATE_GENRES_SELECT_ALL
	EN	All Genres

PLUGIN_SQLPLAYLIST_TEMPLATE_ARTISTS_SELECT_NONE
	EN	No Artists

PLUGIN_SQLPLAYLIST_TEMPLATE_ARTISTS_SELECT_ALL
	EN	All Artists

PLUGIN_SQLPLAYLIST_TEMPLATE_CUSTOM
	EN	Blank playlist

PLUGIN_SQLPLAYLIST_TEMPLATE_ARTISTS_TITLE
	EN	Artists

PLUGIN_SQLPLAYLIST_TEMPLATE_INCLUDING_GENRES
	EN	Playlist including songs for selected genres only

PLUGIN_SQLPLAYLIST_TEMPLATE_INCLUDING_ARTISTS
	EN	Playlist including songs for selected artists only

PLUGIN_SQLPLAYLIST_TEMPLATE_INCLUDING_GENRES_INCLUDING_ARTISTS
	EN	Playlist including songs for selected genres and selected artists only

PLUGIN_SQLPLAYLIST_TEMPLATE_EXCLUDING_GENRES
	EN	Playlist excluding all songs for selected genres

PLUGIN_SQLPLAYLIST_TEMPLATE_EXCLUDING_ARTISTS
	EN	Playlist excluding all songs for selected aritsts

PLUGIN_SQLPLAYLIST_TEMPLATE_EXCLUDING_GENRES_EXCLUDING_ARTISTS
	EN	Playlist excluding all songs for selected aritsts and excluding all songs for selected genres

PLUGIN_SQLPLAYLIST_TEMPLATE_RANDOM
	EN	Playlist with all songs

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED
	EN	Playlist with all top rated songs (4 and 5)

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_INCLUDING_GENRES
	EN	Playlist with all top rated songs (4 and 5) for the selected genres

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_INCLUDING_GENRES_INCLUDING_ARTISTS
	EN	Playlist with all top rated songs (4 and 5) for the selected genres and selected artists only

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_INCLUDING_ARTISTS
	EN	Playlist with all top rated songs (4 and 5) for the selected artists

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_EXCLUDING_GENRES
	EN	Playlist with all top rated songs (4 and 5) excluding songs in selected genres

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_EXCLUDING_ARTISTS
	EN	Playlist with all top rated songs (4 and 5) excluding songs in selected artists

PLUGIN_SQLPLAYLIST_TESTPLAYLIST
	EN	Test

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_EXCLUDING_GENRES_EXCLUDING_ARTISTS
	EN	Playlist with all top rated songs (4 and 5) excluding all songs for selected aritsts and excluding all songs for selected genres

EOF

}

1;

__END__
