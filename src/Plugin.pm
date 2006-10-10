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

if ($::VERSION ge '6.5') {
	eval "use Slim::Schema";
}

# Information on each clients sqlplaylist
my $htmlTemplate = 'plugins/SQLPlayList/sqlplaylist_list.html';
my $ds = getCurrentDS();
my $playLists = undef;
my $playListTypes = undef;
my $sqlerrors = '';

my %disable = (
	'id' => 'disable', 
	'file' => '', 
	'name' => '', 
	'sql' => '', 
	'fulltext' => ''
);
	
sub getDisplayName {
	return 'PLUGIN_SQLPLAYLIST';
}

sub getCurrentPlayList {
	my $client = shift;
	my $currentPlaying = eval { Plugins::DynamicPlayList::Plugin::getCurrentPlayList($client) };
	if ($@) {
		warn("SQLPlayList: Error getting current playlist from DynamicPlayList plugin: $@\n");
	}
	if($currentPlaying) {
		$currentPlaying =~ s/^sqlplaylist_//;
		my $playlist = getPlayList($client,$currentPlaying);
		if(defined($playlist)) {
			$currentPlaying = $playlist->{'id'};
		}else {
			$currentPlaying = undef;
		}
	}
	return $currentPlaying;
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	debugMsg("".($add ? 'Add' : 'Play')."$item\n");
	
	my $currentPlaying = getCurrentPlayList($client);

	# reconstruct the list of options, adding and removing the 'disable' option where applicable
	my $listRef = Slim::Buttons::Common::param($client, 'listRef');
		
	if ($item eq 'disable') {
		pop @$listRef;
		
	# only add disable option if starting a mode from idle state
	} elsif (! $currentPlaying) {
		push @$listRef, \%disable;
	}
	Slim::Buttons::Common::param($client, 'listRef', $listRef);

	my $request;
	if($item eq 'disable') {
		$request = $client->execute(['dynamicplaylist', 'playlist', 'stop']);
	}else {
		$item = "sqlplaylist_".$item;
		$request = $client->execute(['dynamicplaylist', 'playlist', ($add?'add':'play'), $item]);
	}
	if ($::VERSION ge '6.5') {
		# indicate request source
		$request->source('PLUGIN_SQLPLAYLIST');
	}
}

sub getPlayList {
	my $client = shift;
	my $type = shift;
	
	return undef unless $type;

	debugMsg("Get playlist: $type\n");
	if(!$playLists) {
		initPlayLists();
	}
	return undef unless $playLists;
	
	return $playLists->{$type};
}
sub initPlayListTypes {
	if(!$playLists) {
		initPlayLists();
	}
	my %localPlayListTypes = ();
	for my $playlistId (keys %$playLists) {
		my $playlist = $playLists->{$playlistId};
		my $parameters = $playlist->{'parameters'};
		if(defined($parameters)) {
			my $parameter1 = $parameters->{'1'};
			if(defined($parameter1)) {
				if($parameter1->{'type'} eq 'album' || $parameter1->{'type'} eq 'artist' || $parameter1->{'type'} eq 'year' || $parameter1->{'type'} eq 'genre' || $parameter1->{'type'} eq 'playlist') {
					$localPlayListTypes{$parameter1->{'type'}} = 1;
				}
			}
		}
	}
	$playListTypes = \%localPlayListTypes;
}

sub initPlayLists {
	my $playlistDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
	debugMsg("Searching for playlists in: $playlistDir\n");
	
	if (!defined $playlistDir || !-d $playlistDir) {
		debugMsg("Skipping playlist folder scan - playlistdir is undefined.\n");
		return;
	}
	my @dircontents = Slim::Utils::Misc::readDirectory($playlistDir,"sql");

	my %localPlayLists = ();
	
	for my $item (@dircontents) {

		my $url = catfile($playlistDir, $item);

        open(my $fh, $url) or do {
                debugMsg("Couldn't open: $url : $!\n");
                next;
        };

		my $name = undef;
		my $statement = '';
		my $fulltext = '';
    	my @groups = ();
    	my %parameters = ();
        for my $line (<$fh>) {
        	if($name && $line !~ /^\s*--\s*PlaylistGroups\s*[:=]\s*/) {
        		$fulltext .= $line;
        	}
            chomp $line;

			# use "--PlaylistName:" as name of playlist
			$line =~ s/^\s*--\s*PlaylistName\s*[:=]\s*//io;
			
			my $parameter = parseParameter($line);
			if($line =~ /^\s*--\s*PlaylistGroups\s*[:=]\s*/) {
				$line =~ s/^\s*--\s*PlaylistGroups\s*[:=]\s*//io;
				if($line) {
					my @stringGroups = split(/\,/,$line);
					foreach my $item (@stringGroups) {
						# Remove all white spaces
						$item =~ s/^\s+//;
						$item =~ s/\s+$//;
						my @subGroups = split(/\//,$item);
						push @groups,\@subGroups;
					}
				}
				$line = "";
			}elsif($parameter) {
				$parameters{$parameter->{'id'}} = $parameter;
			}
			
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
			my $playlistid = escape($name,"^A-Za-z0-9\-_");
			my %playlist = (
				'id' => $playlistid, 
				'file' => $item, 
				'name' => $name, 
				'sql' => Slim::Utils::Unicode::utf8decode($statement,'utf8') , 
				'fulltext' => Slim::Utils::Unicode::utf8decode($fulltext,'utf8')
			);
			if(scalar(@groups)>0) {
				$playlist{'groups'} = \@groups;
			}
			if(%parameters) {
				$playlist{'parameters'} = \%parameters;
				foreach my $p (keys %parameters) {
					if(defined($playLists) 
						&& defined($playLists->{$playlistid}) 
						&& defined($playLists->{$playlistid}->{'parameters'})
						&& defined($playLists->{$playlistid}->{'parameters'}->{$p})
						&& $playLists->{$playlistid}->{'parameters'}->{$p}->{'name'} eq $parameters{$p}->{'name'}
						&& defined($playLists->{$playlistid}->{'parameters'}->{$p}->{'value'})) {
						
						debugMsg("Use already existing value PlaylistParameter$p=".$playLists->{$playlistid}->{'parameters'}->{$p}->{'value'}."\n");	
						$parameters{$p}->{'value'}=$playLists->{$playlistid}->{'parameters'}->{$p}->{'value'};
					}
				}
			}
			$localPlayLists{$playlistid} = \%playlist;
		}
	}
	$playLists = \%localPlayLists;
	initPlayListTypes();
}


sub initPlugin {
	checkDefaults();
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
	initPlayLists();
	my $currentPlaying = eval { Plugins::DynamicPlayList::Plugin::getCurrentPlayList($client) };
	if ($@) {
		warn("SQLPlayList: Error getting current playlist from DynamicPlayList plugin: $@\n");
	}
	if($currentPlaying) {
		$currentPlaying =~ s/^sqlplaylist_//;
	}
	my $playlist = getPlayList($client,$currentPlaying);
	my $name = undef;
	if($playlist) {
		$name = $playlist->{'name'};
	}
	$params->{'pluginSQLPlayListPlayLists'} = $playLists;
	$params->{'pluginSQLPlayListNowPlaying'} = $name;
	if ($::VERSION ge '6.5') {
		$params->{'pluginSQLPlayListSlimserver65'} = 1;
	}
    if(!UNIVERSAL::can("Plugins::DynamicPlayList::Plugin","getCurrentPlayList")) {
		$params->{'pluginSQLPlayListError'} = "ERROR!!! Cannot find DynamicPlayList plugin, please make sure you have installed and enabled at least DynamicPlayList 1.3"
	}
	
	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

# Draws the plugin's edit playlist web page
sub handleWebEditPlaylist {
	my ($client, $params) = @_;

	if ($params->{'type'}) {
		my $playlist = getPlayList($client,$params->{'type'});
		if($playlist) {
			$params->{'pluginSQLPlayListEditPlayListFile'} = escape($playlist->{'file'});
			$params->{'pluginSQLPlayListEditPlayListName'} = $playlist->{'name'};
			$params->{'pluginSQLPlayListEditPlayListGroups'} = getGroupString($playlist);
			$params->{'pluginSQLPlayListEditPlayListText'} = Slim::Utils::Unicode::utf8decode($playlist->{'fulltext'},'utf8');
			$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($params->{'pluginSQLPlayListEditPlayListFile'});
		}else {
			warn "Cannot find: ".$params->{'type'};
		}
	}

	$params->{'pluginSQLPlayListError'} = undef;
	if ($::VERSION ge '6.5') {
		$params->{'pluginSQLPlayListSlimserver65'} = 1;
	}
	
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editplaylist.html', $params);
}

sub getGroupString {
	my $playlist = shift;

	my $result = undef;
	if(defined($playlist->{'groups'})) {
		foreach my $group (@{$playlist->{'groups'}}) {
			if(defined($result)) {
				$result .= ",";
			}else {
				$result = "";
			}
			my $subresult = undef;
			foreach my $subgroup (@$group) {
				if(defined($subresult)) {
					$subresult .= "/";
				}else {
					$subresult = "";
				}
				$subresult .= $subgroup;
			}
			$result .= $subresult;
		}
	}
	return $result;
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
	my $ds = getCurrentDS();
	if($params->{'text'}) {
		my $playlist = createSQLPlayList(Slim::Utils::Unicode::utf8decode($params->{'text'},'utf8'));
		if($playlist) {
			if(handleWebTestParameters($client,$params,$playlist)) {
				my $sql = $playlist->{'sql'};
				if(defined($playlist->{'parameters'})) {
					$sql = replaceParametersInSQL($sql,$playlist->{'parameters'});
				}
				my $tracks = executeSQLForPlaylist($sql);
				my @resultTracks;
				my $itemNumber = 0;
				foreach my $track (@$tracks) {
				  	my %trackInfo = ();
		            displayAsHTML('track', \%trackInfo, $track);
				  	$trackInfo{'title'} = Slim::Music::Info::standardTitle(undef,$track);
				  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
		            $trackInfo{'itemobj'}          = $track;
				  	push @resultTracks,\%trackInfo;
				}
				if(@resultTracks && scalar(@resultTracks)>0) {
					$params->{'pluginSQLPlayListEditPlayListTestResult'} = \@resultTracks;
				}
			}
		}
	}

	if($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginSQLPlayListError'} = $sqlerrors;
	}else {
		$params->{'pluginSQLPlayListError'} = undef;
	}
	if ($::VERSION ge '6.5') {
		$params->{'pluginSQLPlayListSlimserver65'} = 1;
	}
}

sub handleWebTestParameters {
	my ($client,$params,$playlist) = @_;
	my $parameterId = 1;
	my @parameters = ();
	
	my $i=1;
	while(defined($params->{'sqlplaylist_parameter_'.$i})) {
		$parameterId = $parameterId +1;
		if($params->{'sqlplaylist_parameter_changed'} eq $i) {
			last;
		}
		$i++;
	}
	if(defined($playlist->{'parameters'}->{$parameterId})) {
		for(my $i=1;$i<$parameterId;$i++) {
			my @parameterValues = ();
			my $parameter = $playlist->{'parameters'}->{$i};
			addParameterValues($client,\@parameterValues,$parameter);
			my %webParameter = (
				'parameter' => $parameter,
				'values' => \@parameterValues,
				'value' => $params->{'sqlplaylist_parameter_'.$i}
			);
			my %value = (
				'id' => $params->{'sqlplaylist_parameter_'.$i}
			);
			$client->param('sqlplaylist_parameter_'.$i,\%value);
			push @parameters,\%webParameter;
		}
		
		my $parameter = $playlist->{'parameters'}->{$parameterId};
		debugMsg("Getting values for: ".$parameter->{'name'}."\n");
		my @parameterValues = ();
		addParameterValues($client,\@parameterValues,$parameter);
		my %currentParameter = (
			'parameter' => $parameter,
			'values' => \@parameterValues
		);
		push @parameters,\%currentParameter;
		$params->{'pluginSQLPlayListTestParameters'} = \@parameters;
		return 0;
	}else {
		for(my $i=1;$i<$parameterId;$i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $params->{'sqlplaylist_parameter_'.$i};
		}
		return 1;
	}
}

sub addParameterValues {
	my $client = shift;
	my $listRef = shift;
	my $parameter = shift;
	
	debugMsg("Getting values for ".$parameter->{'name'}." of type ".$parameter->{'type'}."\n");
	my $sql = undef;
	if(lc($parameter->{'type'}) eq 'album') {
		$sql = "select id,title from albums order by titlesort";
	}elsif(lc($parameter->{'type'}) eq 'artist') {
		$sql = "select id,name from contributors where namesort is not null order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'genre') {
		$sql = "select id,name from genres order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'year') {
		$sql = "select year,year from tracks where year is not null group by year order by year";
	}elsif(lc($parameter->{'type'}) eq 'playlist') {
		$sql = "select playlist_track.playlist,tracks.title from tracks, playlist_track where tracks.id=playlist_track.playlist group by playlist_track.playlist order by titlesort";
	}elsif(lc($parameter->{'type'}) eq 'list') {
		my $value = $parameter->{'definition'};
		if(defined($value) && $value ne "" ) {
			my @values = split(/,/,$value);
			if(@values) {
				for my $valueItem (@values) {
					my @valueItemArray = split(/:/,$valueItem);
					my $id = shift @valueItemArray;
					my $name = shift @valueItemArray;
					
					if(defined($id)) {
						my %listitem = (
							'id' => $id
						);
						if(defined($name)) {
							$listitem{'name'}=$name;
						}else {
							$listitem{'name'}=$id;
						}
					  	push @$listRef, \%listitem;
					}
				}
			}else {
				debugMsg("Error, invalid parameter value: $value\n");
			}
		}
	}elsif(lc($parameter->{'type'}) eq 'custom') {
		if(defined($parameter->{'definition'}) && lc($parameter->{'definition'}) =~ /^select/ ) {
			$sql = $parameter->{'definition'};
			for (my $i=1;$i<$parameter->{'id'};$i++) {
				my $parameter = $client->param('sqlplaylist_parameter_'.$i);
				my $value = $parameter->{'id'};
				my $parameterid = "\'PlaylistParameter".$i."\'";
				debugMsg("Replacing ".$parameterid." with ".$value."\n");
				$sql =~ s/$parameterid/$value/g;
			}
		}
	}
	
	if(defined($sql)) {
		my $dbh = getCurrentDBH();
    	eval {
			my $sth = $dbh->prepare( $sql );
			debugMsg("Executing value list: $sql\n");
			$sth->execute() or do {
	            debugMsg("Error executing: $sql\n");
	            $sql = undef;
			};
			if(defined($sql)) {
				my $id;
				my $name;
				$sth->bind_columns( undef, \$id,\$name);
				while( $sth->fetch() ) {
					my %listitem = (
						'id' => $id,
						'name' => Slim::Utils::Unicode::utf8decode($name,'utf8')
					);
				  	push @$listRef, \%listitem;
			  	}
			  	debugMsg("Added ".scalar(@$listRef)." items to value list\n");
			}
			$sth->finish();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}		
	}
}

# Returns a hash whose keys are the genres in the db
sub getGenres {
	my ($client) = @_;
	my %clientGenres = ();

	if ($::VERSION ge '6.5') {
		# Should use genre.name in following find, but a bug in find() doesn't allow this
        # XXXX - how does the above comment translate into DBIx::Class world?
        my $rs = Slim::Schema->search('Genre');

        # Extract each genre name into a hash
        for my $genre ($rs->all) {
                $clientGenres{$genre->name} = {
		                # Put the name here as well so the hash can be passed to
		                # INPUT.Choice as part of listRef later on
                        'id'      => $genre->id,
                        'name'    => $genre->name,
                };
        }
	}else {
		# Should use genre.name in following find, but a bug in find() doesn't allow this	
	   	my $items = $ds->find({
			'field'  => 'genre',
			'cache'  => 0,
		});
		
		# Extract each genre name into a hash
		foreach my $item (@$items) {
			$clientGenres{$item->{'name'}} = {
			                                 # Put the name here as well so the hash can be passed to
			                                 # INPUT.Choice as part of listRef later on
			                                 name    => $item->{'name'},
			                                 id      => $item->{'id'},
										 };
		}
	}
	return %clientGenres;
}

sub getArtists {
	my ($client) =@_;
	my %clientArtists = ();
	
	if ($::VERSION ge '6.5') {
        my $rs = Slim::Schema->search('Contributor',undef,{'order_by' => 'name'});

		for my $item ($rs->all) {
			$clientArtists{escape($item->name)} = {
				name => $item->name,
				id => $item->id,
			};
        }
	}else {
		my $items = $ds->find({
			'field'  => 'artist',
			'sortBy' => 'name',
			'cache'  => 0,
		});
		
		for my $item (@$items) {
			$clientArtists{escape($item->{'name'})} = {
				name => $item->{'name'},
				id => $item->{'id'},
			};
		}
	}
	
	return %clientArtists;
}

# Draws the plugin's edit playlist web page
sub handleWebNewPlaylist {
	my ($client, $params) = @_;

#	foreach my $param (keys %$params) {
#		debugMsg("Got: $param = ".$params->{$param}."\n");
#	}

	$params->{'pluginSQLPlayListError'} = undef;
	$params->{'pluginSQLPlayListGenreList'} = {getGenres($client)};
	$params->{'pluginSQLPlayListArtistList'} = {getArtists($client)};
	if ($::VERSION ge '6.5') {
		$params->{'pluginSQLPlayListSlimserver65'} = 1;
	}
	
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
	if ($::VERSION ge '6.5') {
		$params->{'pluginSQLPlayListSlimserver65'} = 1;
	}
	my $genreListString = Slim::Utils::Unicode::utf8decode(getGenreListString($client,$params),'utf8');
	my $artistListString = Slim::Utils::Unicode::utf8decode(getArtistListString($client,$params),'utf8');
	my $maxLengthValue = $params->{'maxtracklength'};
	if(!defined($maxLengthValue)) {
		$maxLengthValue=0;
	}
	my $minLengthValue = $params->{'mintracklength'};
	if(!defined($minLengthValue)) {
		$minLengthValue=0;
	}
	my $maxYear = $params->{'maxtrackyear'};
	if(!defined($maxYear)) {
		$maxYear=0;
	}
	my $minYear = $params->{'mintrackyear'};
	if(!defined($minYear)) {
		$minYear=0;
	}
	my $notRepeat = $params->{'notrepeat'};
	my $includeComment = getCommentString($params->{'includecomment'});
	my $excludeComment = getCommentString($params->{'excludecomment'});
	debugMsg("Genres = ".$genreListString."\n");
	debugMsg("Artists = ".$artistListString."\n");
	if($params->{'type'} eq "random") {
		my $sql = "select tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
		}
		if($excludeComment) {
			if($notRepeat) {
				$sql .= " and\n\t";
			}else {
				$sql .= "\n\twhere ";
			}
			$sql .= "excludecomments.id is null";
		}
		if($maxLengthValue>0) {
			if($excludeComment || $notRepeat) {
				$sql .= " and\n\t";
			}else {
				$sql .= "\n\twhere ";
			}
			$sql .= "tracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			if($maxLengthValue>0 || $excludeComment || $notRepeat) {
				$sql .= " and \n\t"; 
			}else {
				$sql .= "\n\twhere ";
			}
			$sql .= "tracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			if($maxLengthValue>0 || $minLengthValue>0 || $excludeComment || $notRepeat) {
				$sql .= " and \n\t"; 
			}else {
				$sql .= "\n\twhere ";
			}
			$sql .= "tracks.year<=$maxYear";
		}
		if($minYear>0) {
			if($maxLengthValue>0 || $minLengthValue>0 || $maxYear>0 || $excludeComment || $notRepeat) {
				$sql .= " and \n\t"; 
			}else {
				$sql .= "\n\twhere ";
			}
			$sql .= "tracks.year>=$minYear";
		}
		if($includeComment) {
			$sql .= "\ngroup by tracks.id";
		}
		$sql .= "\norder by $orderBy limit 10;";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "includinggenres") {
		my $sql = "select tracks.url from tracks \n\tjoin genre_track on\n\t\ttracks.id=genre_track.track\n\tjoin genres on\n\t\tgenre_track.genre=genres.id";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "tracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenres.name in (";
			$sql .= $genreListString;
			$sql .= ")";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		if($includeComment) {
			$sql .= "\ngroup by tracks.id";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "includinggenresincludingartists") {
		my $sql = "select tracks.url from tracks\n\tjoin genre_track on\n\t\ttracks.id=genre_track.track\n\tjoin genres on\n\t\tgenre_track.genre=genres.id\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin contributors on\n\t\tcontributor_track.contributor=contributors.id";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "tracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
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
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "includingartists") {
		my $sql = "select tracks.url from tracks\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin contributors on\n\t\tcontributor_track.contributor=contributors.id";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "tracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributors.name in (";
			$sql .= $artistListString;
			$sql .= ")";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedincludinggenres") {
		my $sql = "select tracks.url from tracks\n\tjoin genre_track on\n\t\ttracks.id=genre_track.track\n\tjoin genres on\n\t\tgenre_track.genre=genres.id\n\tjoin track_statistics on\n\t\ttracks.url=track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80 and\n\t\ttracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenres.name in (";
			$sql .= $genreListString;
			$sql .= ")";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedincludingartists") {
		my $sql = "select tracks.url from tracks\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin contributors on\n\t\tcontributor_track.contributor=contributors.id\n\tjoin track_statistics on\n\t\ttracks.url=track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80 and\n\t\ttracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributors.name in (";
			$sql .= $artistListString;
			$sql .= ")";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedincludinggenresincludingartists") {
		my $sql = "select tracks.url from tracks\n\tjoin genre_track on\n\t\ttracks.id=genre_track.track\n\tjoin genres on\n\t\tgenre_track.genre=genres.id\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin contributors on\n\t\tcontributor_track.contributor=contributors.id\n\tjoin track_statistics on \n\t\ttracks.url=track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80 and\n\t\ttracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
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
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenres") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "select distinct tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		$sql .= "\n\tleft join genre_track_withname on \n\t\ttracks.id=genre_track_withname.track";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenre_track_withname.name in(";
			$sql .= $genreListString;
			$sql .= ")"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($genreListString ne "") {
			$sql .= "genre_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludingartists") {
		my $sql = "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect distinct contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		$sql .= "\n\tleft join contributor_track_withname on \n\t\ttracks.id=contributor_track_withname.track";
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributor_track_withname.name in(";
			$sql .= $artistListString;
			$sql .= ")"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($artistListString ne "") {
			$sql .= "contributor_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenresexcludingartists") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect distinct contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		$sql .= "\n\tleft join genre_track_withname on \n\t\ttracks.id=genre_track_withname.track";
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
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($genreListString ne "") {
			$sql .= "genre_track_withname.track is null and ";
		}
		if($artistListString ne "") {
			$sql .= "contributor_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenressqlite") {
		my $sql = "select tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($genreListString ne "") {
			$sql .= "\n\t\tnot exists (select * from genre_track,genres where";
			$sql .= "\n\t\t\tgenre=genres.id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $genreListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		if($includeComment) {
			$sql .= "\ngroup by tracks.id";
		}
		$sql .= "\n\t\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($artistListString ne "") {
			$sql .= "\n\t\tnot exists (select * from contributor_track,contributors where";
			$sql .= "\n\t\t\tcontributor=contributors.id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $artistListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		if($includeComment) {
			$sql .= "\ngroup by tracks.id";
		}
		$sql .= "\n\t\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenresexcludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($genreListString ne "") {
			$sql .= "\n\t\tnot exists (select * from genre_track,genres where";
			$sql .= "\n\t\t\tgenre=genres.id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $genreListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		if($artistListString ne "") {
			$sql .= "\n\t\tnot exists (select * from contributor_track,contributors where";
			$sql .= "\n\t\t\tcontributor=contributors.id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $artistListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		if($includeComment) {
			$sql .= "\ngroup by tracks.id";
		}
		$sql .= "\n\t\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenres") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "select distinct tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		$sql .= "\n\tleft join genre_track_withname on \n\t\ttracks.id=genre_track_withname.track";
		if($genreListString ne "") {
			$sql .= " and \n\t\tgenre_track_withname.name in(";
			$sql .= $genreListString;
			$sql .= ")"
		}
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($genreListString ne "") {
			$sql .= "genre_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludingartists") {
		my $sql = "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect distinct contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		$sql .= "\n\tleft join contributor_track_withname on \n\t\ttracks.id=contributor_track_withname.track";
		if($artistListString ne "") {
			$sql .= " and \n\t\tcontributor_track_withname.name in(";
			$sql .= $artistListString;
			$sql .= ")"
		}
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($artistListString ne "") {
			$sql .= "contributor_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenresexcludingartists") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect distinct contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		$sql .= "\n\tleft join genre_track_withname on \n\t\ttracks.id=genre_track_withname.track";
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
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($genreListString ne "") {
			$sql .= "genre_track_withname.track is null and ";
		}
		if($artistListString ne "") {
			$sql .= "contributor_track_withname.track is null and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenressqlite") {
		my $sql = "select tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($genreListString ne "") {
			$sql .= "\n\t\tnot exists (select * from genre_track,genres where";
			$sql .= "\n\t\t\tgenre=genres.id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $genreListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($artistListString ne "") {
			$sql .= "\n\t\tnot exists (select * from contributor_track,contributors where";
			$sql .= "\n\t\t\tcontributor=contributors.id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $artistListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenresexcludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		$sql .= "\n\tleft join track_statistics on\n\t\ttrack_statistics.url=tracks.url";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		if($genreListString ne "") {
			$sql .= "\n\t\tnot exists (select * from genre_track,genres where";
			$sql .= "\n\t\t\tgenre=genres.id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $genreListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		if($artistListString ne "") {
			$sql .= "\n\t\tnot exists (select * from contributor_track,contributors where";
			$sql .= "\n\t\t\tcontributor=contributors.id and";
			$sql .= "\n\t\t\tname in(";
			$sql .= $artistListString;
			$sql .= ") and ";
			$sql .= "\n\t\t\ttrack=tracks.id) and ";
		}
		$sql .= "\n\t\ttracks.audio=1 and\n\t\ttrack_statistics.rating>=80";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "toprated") {
		my $sql = "select tracks.url from tracks\n\tjoin track_statistics on\n\t\ttracks.url = track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		if($includeComment) {
			$sql .= "\ngroup by tracks.id";
		}
		$sql .= "\n\torder by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "withspecificrating") {
		my $sql = "-- PlaylistParameter1:list:Select rating:20:*,40:**,60:***,80:****,100:*****";
		$sql .= "\nselect tracks.url from tracks\n\tjoin track_statistics on\n\t\ttracks.url = track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating=\'PlaylistParameter1\'";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		if($includeComment) {
			$sql .= "\ngroup by tracks.id";
		}
		$sql .= "\n\torder by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedforyear") {
		my $sql = "-- PlaylistParameter1:year:Select year:";
		$sql .= "\nselect tracks.url from tracks\n\tjoin track_statistics on\n\t\ttracks.url = track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "tracks.year=\'PlaylistParameter1\' and\n\t\ttrack_statistics.rating>=80";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($includeComment) {
			$sql .= "\ngroup by tracks.id";
		}
		$sql .= "\n\torder by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedforalbum") {
		my $sql = "-- PlaylistParameter1:album:Select album:";
		$sql .= "\nselect tracks.url from tracks\n\tjoin track_statistics on\n\t\ttracks.url = track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "tracks.album=\'PlaylistParameter1\' and\n\t\ttrack_statistics.rating>=80";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		if($includeComment) {
			$sql .= "\ngroup by tracks.id";
		}
		$sql .= "\n\torder by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedforgenre") {
		my $sql = "-- PlaylistParameter1:genre:Select genre:";
		$sql .= "\nselect tracks.url from tracks\n\tjoin genre_track on\n\t\ttracks.id=genre_track.track\n\tjoin track_statistics on\n\t\ttracks.url=track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80 and\n\t\ttracks.audio=1";
		$sql .= " and \n\t\tgenre_track.genre=\'PlaylistParameter1\'";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedforartist") {
		my $sql = "-- PlaylistParameter1:artist:Select artist:";
		$sql .= "\nselect tracks.url from tracks\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin track_statistics on\n\t\ttracks.url=track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80 and\n\t\ttracks.audio=1";
		$sql .= " and \n\t\tcontributor_track.contributor=\'PlaylistParameter1\'";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedforplaylist") {
		my $sql = "-- PlaylistParameter1:playlist:Select playlist:";
		$sql .= "\nselect tracks.url from tracks\n\tjoin playlist_track on\n\t\ttracks.id=playlist_track.track\n\tjoin track_statistics on\n\t\ttracks.url=track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80 and\n\t\ttracks.audio=1";
		$sql .= " and \n\t\tplaylist_track.playlist=\'PlaylistParameter1\'";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "withspecificratingforartist") {
		my $sql = "-- PlaylistParameter1:list:Select rating:20:*,40:**,60:***,80:****,100:*****";
		$sql .= "\n-- PlaylistParameter2:custom:Select artist:select contributors.id,contributors.name from tracks join contributor_track on tracks.id=contributor_track.track join contributors on contributor_track.contributor=contributors.id left join track_statistics on tracks.url=track_statistics.url where tracks.audio=1 and track_statistics.rating=\'PlaylistParameter1\' group by contributors.id order by contributors.namesort";
		$sql .= "\nselect tracks.url from tracks\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin track_statistics on\n\t\ttracks.url=track_statistics.url";
		if($includeComment) {
			$sql .= "\n\tjoin comments on\n\t\ttracks.id=comments.track and comments.value like $includeComment"
		}
		if($excludeComment) {
			$sql .= "\n\tleft join comments as excludecomments on\n\t\ttracks.id=excludecomments.track and excludecomments.value like $excludeComment"
		}
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating=\'PlaylistParameter1\' and\n\t\ttracks.audio=1";
		$sql .= " and \n\t\tcontributor_track.contributor=\'PlaylistParameter2\'";
		if($excludeComment) {
			$sql .= " and \n\t\texcludecomments.id is null";
		}
		if($maxLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			$sql .= " and\n\t\ttracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			$sql .= " and\n\t\ttracks.year<=$maxYear";
		}
		if($minYear>0) {
			$sql .= " and\n\t\ttracks.year>=$minYear";
		}
		$sql .= "\ngroup by tracks.id";
		$sql .= "\n\t order by $orderBy limit 10;\n";
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

sub getCommentString {
	my $comment = shift;
	my $dbh = getCurrentDBH();
	if($comment) {
		$comment = $dbh->quote("%".$comment."%");
	}	
	return $comment;
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
	my $ds = getCurrentDS();
	my $dbh = getCurrentDBH();
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
		$params->{'pluginSQLPlayListError'} = 'All fields besides groups are mandatory';
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
	if($playlist && $playlist->{'file'} ne unescape($params->{'file'})) {
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
		$params->{'pluginSQLPlayListError'} = 'All fields besides groups are mandatory';
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
				debugMsg("Deleteing playlist: ".$playlist->{'file'}."\n");
				my $url = catfile($playlistDir, unescape($playlist->{'file'}));
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
		if($params->{'groups'}) {
			print $fh "-- PlaylistGroups: ".$params->{'groups'}."\n";
		}
		print $fh $params->{'text'};
		debugMsg("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginSQLPlayListError'}) {
		$params->{'pluginSQLPlayListEditPlayListFile'} = $params->{'file'};
		$params->{'pluginSQLPlayListEditPlayListText'} = $params->{'text'};
		$params->{'pluginSQLPlayListEditPlayListName'} = $params->{'name'};
		$params->{'pluginSQLPlayListEditPlayListGroups'} = $params->{'groups'};
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
		handlePlayOrAdd($client, $params->{'type'}, $params->{'addOnly'});
	}
	return handleWebList($client, $params);
}


# Handles settings changes from plugin's web page
sub handleWebSettings {
	my ($client, $params) = @_;

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
	my $prefVal = Slim::Utils::Prefs::get('plugin_sqlplaylist_playlist_directory');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_sqlplaylist_playlist_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_playlist_directory', $dir);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_sqlplaylist_showmessages');
	if (! defined $prefVal) {
		# Default to not show debug messages
		debugMsg("Defaulting plugin_sqlplaylist_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_showmessages', 0);
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_sqlplaylist_playlist_directory','plugin_sqlplaylist_showmessages'],
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
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_SQLPLAYLIST_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_SQLPLAYLIST_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_sqlplaylist_showmessages"); }
		},		
	plugin_sqlplaylist_playlist_directory => {
			'validate' => \&validateIsDirWrapper
			,'PrefChoose' => string('PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY')
			,'changeIntro' => string('PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory"); }
		},
	);
	return (\%setupGroup,\%setupPrefs);
}
sub replaceParametersInSQL {
	my $sql = shift;
	my $parameters = shift;
	
	if(defined($parameters)) {
		foreach my $key (keys %$parameters) {
			my $parameter = $parameters->{$key};
			my $value = $parameter->{'value'};
			my $parameterid = "\'PlaylistParameter".$parameter->{'id'}."\'";
			debugMsg("Replacing ".$parameterid." with ".$value."\n");
			$sql =~ s/$parameterid/$value/g;
		}
	}
	return $sql;
}
sub getTracksForPlaylist {
	my $client = shift;
	my $playlist = shift;
	my $limit = shift;
	my $parameters = shift;

	my $sqlstatements = $playlist->{'sql'};
	my $dbh = getCurrentDBH();
	$sqlstatements = replaceParametersInSQL($sqlstatements,$parameters);
	my $result= executeSQLForPlaylist($sqlstatements,$limit);
	
	return $result;
}

sub parseParameter {
	my $line = shift;
	
	if($line =~ /^\s*--\s*PlaylistParameter\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistParameter\s*(\d)\s*[:=]\s*([^:]+):\s*([^:]*):\s*(.*)$/;
		my $parameterId = $1;
		my $parameterType = $2;
		my $parameterName = $3;
		my $parameterDefinition = $4;

		$parameterType =~ s/^\s+//;
		$parameterType =~ s/\s+$//;

		$parameterName =~ s/^\s+//;
		$parameterName =~ s/\s+$//;

		$parameterDefinition =~ s/^\s+//;
		$parameterDefinition =~ s/\s+$//;

		if($parameterId && $parameterName && $parameterType) {
			my %parameter = (
				'id' => $parameterId,
				'type' => $parameterType,
				'name' => $parameterName,
				'definition' => $parameterDefinition
			);
			return \%parameter;
			debugMsg("Adding parameter: $parameterId, $parameterType, $parameterName, $parameterDefinition\n");
		}else {
			debugMsg("Error in parameter: $line\n");
			debugMsg("Parameter values: Id=$parameterId, Type=$parameterType, Name=$parameterName, Definition=$parameterDefinition\n");
			return undef;
		}
	}
	return undef;
}	
sub createSQLPlayList {
	my $sqlstatements = shift;
	my $sql = '';
	my %parameters = ();
    for my $line (split(/[\n\r]/,$sqlstatements)) {
        chomp $line;

		my $parameter = parseParameter($line);
		if(defined($parameter)) {
			$parameters{$parameter->{'id'}} = $parameter;
		}
		
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
    if($sql) {
	    my %playlist = (
	    	'sql' => $sql
	    );
	    if(defined(%parameters)) {
	    	$playlist{'parameters'} = \%parameters;
	    }
	    	
	    return \%playlist;
	}else {
		return undef;
	}
}
sub executeSQLForPlaylist {
	my $sqlstatements = shift;
	my $limit = shift;
	my @result;
	my $ds = getCurrentDS();
	my $dbh = getCurrentDBH();
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
				  my $track = objectForUrl($url);
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

	if(!$playLists) {
		initPlayLists();
	}
	
	my %result = ();
	
	foreach my $playlist (sort keys %$playLists) {
		my $playlistid = "sqlplaylist_".$playlist;
		my $current = $playLists->{$playlist};
		my %currentResult = (
			'id' => $playlist,
			'name' => $current->{'name'},
			'url' => "plugins/SQLPlayList/sqlplaylist_editplaylist.html?type=".escape($playlist)
		);
		if(defined($current->{'parameters'})) {
			my $parameters = $current->{'parameters'};
			foreach my $pk (%$parameters) {
				my %parameter = (
					'id' => $pk,
					'type' => $parameters->{$pk}->{'type'},
					'name' => $parameters->{$pk}->{'name'},
					'definition' => $parameters->{$pk}->{'definition'}
				);
				$currentResult{'parameters'}->{$pk} = \%parameter;
			}
		}
		if($current->{'groups'} && scalar($current->{'groups'})>0) {
			$currentResult{'groups'} = $current->{'groups'};
		}
		$result{$playlistid} = \%currentResult;
	}
	
	return \%result;
}

sub getNextDynamicPlayListTracks {
	my ($client,$dynamicplaylist,$limit,$offset,$parameters) = @_;
	
	debugMsg("Getting tracks for: ".$dynamicplaylist->{'id'}."\n");
	my $playlist = getPlayList($client,$dynamicplaylist->{'id'});
	my $result = getTracksForPlaylist($client,$playlist,$limit,$parameters);
	
	return \@{$result};
}

sub validateIsDirWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::isDir($arg);
	}else {
		return Slim::Web::Setup::validateIsDir($arg);
	}
}

sub validateTrueFalseWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::trueFalse($arg);
	}else {
		return Slim::Web::Setup::validateTrueFalse($arg);
	}
}

sub objectForUrl {
	my $url = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Schema->objectForUrl({
			'url' => $url
		});
	}else {
		return getCurrentDS()->objectForUrl($url,undef,undef,1);
	}
}

sub getCurrentDBH {
	if ($::VERSION ge '6.5') {
		return Slim::Schema->storage->dbh();
	}else {
		return Slim::Music::Info::getCurrentDataStore()->dbh();
	}
}

sub getCurrentDS {
	if ($::VERSION ge '6.5') {
		return 'Slim::Schema';
	}else {
		return Slim::Music::Info::getCurrentDataStore();
	}
}

sub commit {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit();
	}
}

sub rollback {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->rollback();
	}
}

sub displayAsHTML {
	my $type = shift;
	my $form = shift;
	my $item = shift;
	
	if ($::VERSION ge '6.5') {
		$item->displayAsHTML($form);
	}else {
		my $ds = getCurrentDS();
		my $fieldInfo = Slim::DataStores::Base->fieldInfo;
        my $levelInfo = $fieldInfo->{$type};
        &{$levelInfo->{'listItem'}}($ds, $form, $item);
	}
}

sub getLinkAttribute {
	my $attr = shift;
	if ($::VERSION ge '6.5') {
		if($attr eq 'artist') {
			$attr = 'contributor';
		}
		return $attr.'.id';
	}
	return $attr;
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

PLUGIN_SQLPLAYLIST_CONTEXT_CHOOSE_BELOW
	EN	Choose a playlist with music from your library related to

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

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST_GROUPS
	EN	Groups

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

PLUGIN_SQLPLAYLIST_TEMPLATE_MAXTRACKLENGTH
	EN	Max track length (in seconds)

PLUGIN_SQLPLAYLIST_TEMPLATE_MINTRACKLENGTH
	EN	Min track length (in seconds)

PLUGIN_SQLPLAYLIST_TEMPLATE_MAXTRACKYEAR
	EN	Only include tracks before or equal to this year

PLUGIN_SQLPLAYLIST_TEMPLATE_MINTRACKYEAR
	EN	Only include tracks after or equal to this year

PLUGIN_SQLPLAYLIST_TEMPLATE_NOTREPEAT
	EN	Do not repeat tracks within same playlist

PLUGIN_SQLPLAYLIST_NEXT
	EN	Next

PLUGIN_SQLPLAYLIST_TEST_CHOOSE_PARAMETERS
	EN	This playlist requires parameters, please select values

PLUGIN_SQLPLAYLIST_TEMPLATE_PARAMETER_PLAYLISTS
	EN	Playlists with user selectable parameters

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORYEAR
	EN	Playlist with top rated songs (4 and 5) for user selectable year

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORGENRE
	EN	Playlist with top rated songs (4 and 5) for user selectable genre

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORARTIST
	EN	Playlist with top rated songs (4 and 5) for user selectable artist

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORALBUM
	EN	Playlist with top rated songs (4 and 5) for user selectable album

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORPLAYLIST
	EN	Playlist with top rated songs (4 and 5) for user selectable playlist

PLUGIN_SQLPLAYLIST_TEMPLATE_WITHSPECIFICRATING
	EN	Playlist with songs with user selectable rating

PLUGIN_SQLPLAYLIST_TEMPLATE_WITHSPECIFICRATINGFORARTIST
	EN	Playlist with songs with user selectable rating and artist

PLUGIN_SQLPLAYLIST_TEMPLATE_TRACKSTAT_PLAYLISTS
	EN	All the following playlists requires that the TrackStat plugin is installed

PLUGIN_SQLPLAYLIST_TEMPLATE_INCLUDE_COMMENT
	EN	Include tracks with COMMENT tag

PLUGIN_SQLPLAYLIST_TEMPLATE_EXCLUDE_COMMENT
	EN	Exclude tracks with COMMENT tag
EOF

}

1;

__END__
