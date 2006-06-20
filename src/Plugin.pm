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

if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
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

# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;

	my $id = undef;
	my $name = '';
	if($item) {
		$id = $item->{'id'};
		$name = $item->{'name'};
	}
	my $currentPlaying = getCurrentPlayList($client);
	# if showing the current mode, show altered string
	if ($currentPlaying && ($id eq $currentPlaying)) {
		return string('PLUGIN_SQLPLAYLIST_PLAYING')." ".$name;
		
	# if a mode is active, handle the temporarily added disable option
	} elsif ($id eq 'disable' && $currentPlaying) {
		return string('PLUGIN_SQLPLAYLIST_PRESS_RIGHT');
	} else {
		return $name;
	}
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	my $currentPlaying = getCurrentPlayList($client);
	# Put the right arrow by genre filter and notesymbol by mixes
	if ($item->{'id'} eq 'disable') {
		return [undef, Slim::Display::Display::symbol('rightarrow')];
	}elsif (!$currentPlaying || $item->{'id'} ne $currentPlaying) {
		if(defined($item->{'parameters'})) {
			return [Slim::Display::Display::symbol('notesymbol'), Slim::Display::Display::symbol('rightarrow')];
		}else {
			return [undef, Slim::Display::Display::symbol('notesymbol')];
		}
	} elsif(defined($item->{'parameters'})) {
			return [undef, Slim::Display::Display::symbol('rightarrow')];
	} else {
		return [undef, undef];
	}
}

# Returns the display text for the currently selected item in the menu
sub getChooseParametersDisplayText {
	my ($client, $item) = @_;

	my $name = '';
	if($item) {
		$name = $item->{'name'};
	}
	return $name;
}

# Returns the overlay to be display next to items in the menu
sub getChooseParametersOverlay {
	my ($client, $item) = @_;

	return [undef, Slim::Display::Display::symbol('rightarrow')];
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
				if($parameter1->{'type'} eq 'album' || $parameter1->{'type'} eq 'artist' || $parameter1->{'type'} eq 'year' || $parameter1->{'type'} eq 'genre') {
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
			}elsif($line =~ /^\s*--\s*PlaylistParameter\s*\d\s*[:=]\s*/) {
				$line =~ m/^\s*--\s*PlaylistParameter\s*(\d)\s*[:=]\s*([^:]+):\s*([^:]*):\s*(.*)$/;
				my $parameterId = $1;
				my $parameterType = $2;
				my $parameterName = $3;
				my $parameterValue = $4;

				$parameterType =~ s/^\s+//;
				$parameterType =~ s/\s+$//;

				$parameterName =~ s/^\s+//;
				$parameterName =~ s/\s+$//;

				$parameterValue =~ s/^\s+//;
				$parameterValue =~ s/\s+$//;

				if($parameterId && $parameterName && $parameterType) {
					my %parameter = (
						'id' => $parameterId,
						'type' => $parameterType,
						'name' => $parameterName,
						'valuedefinition' => $parameterValue
					);
					$parameters{$parameterId} = \%parameter;
					debugMsg("Adding parameter: $parameterId, $parameterType, $parameterName, $parameterValue\n");
				}else {
					debugMsg("Error in parameter: $line\n");
					debugMsg("Parameter values: Id=$parameterId, Type=$parameterType, Name=$parameterName, Value=$parameterValue\n");
				}
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
	}elsif(lc($parameter->{'type'}) eq 'list') {
		my $value = $parameter->{'valuedefinition'};
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
		if(defined($parameter->{'valuedefinition'}) && lc($parameter->{'valuedefinition'}) =~ /^select/ ) {
			$sql = $parameter->{'valuedefinition'};
			for (my $i=1;$i<$parameter->{'id'};$i++) {
				my $parameter = $client->param('sqlplaylist_mixparameter_'.$i);
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
			$sqlerrors .= $DBI::errstr."<br>";
		    warn "Database error: $DBI::errstr\n";
		}		
	}
}
sub setChooseParametersMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $parameterId = $client->param('sqlplaylist_nextparameter');
	my $playlist = $client->param('sqlplaylist_selectedplaylist');
	
	my $parameter= $playlist->{'parameters'}->{$parameterId};

	my @listRef = ();
	addParameterValues($client,\@listRef, $parameter);

	my $name = $parameter->{'name'};
	my %params = (
		header     => "$name {count}",
		listRef    => \@listRef,
		name       => \&getChooseParametersDisplayText,
		overlayRef => \&getChooseParametersOverlay,
		modeName   => 'PLUGIN.SQLPLayList.ChooseParameters',
		onRight    => sub {
			my ($client, $item) = @_;
			requestNextParameterAndPlayOrAdd($client,$item,$parameterId,$playlist);
		},
		onPlay    => sub {
			my ($client, $item) = @_;
			requestNextParameterAndPlayOrAdd($client,$item,$parameterId,$playlist,0);
		},
		onAdd    => sub {
			my ($client, $item) = @_;
			requestNextParameterAndPlayOrAdd($client,$item,$parameterId,$playlist,1);
		},
		sqlplaylist_nextparameter => $parameterId,
		sqlplaylist_selectedplaylist => $playlist,
		sqlplaylist_addonly => $client->param('sqlplaylist_addonly')
	);
	for(my $i=1;$i<$parameterId;$i++) {
		my $item = $client->param('sqlplaylist_mixparameter_'.$i);
		$params{'sqlplaylist_mixparameter_'.$i} = $item;
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub requestNextParameterAndPlayOrAdd {
	my $client = shift;
	my $item = shift;
	my $parameterId = shift;
	my $playlist = shift;
	my $addOnly = shift;
	
	if(!defined($addOnly)) {
		$addOnly = $client->param('sqlplaylist_addonly');
	}
	$client->param('sqlplaylist_mixparameter_'.$parameterId,$item);
	if(defined($playlist->{'parameters'}->{$parameterId+1})) {
		my %nextParameter = (
			'sqlplaylist_nextparameter' => $parameterId+1,
			'sqlplaylist_selectedplaylist' => $playlist,
			'sqlplaylist_addonly' => $addOnly
		);
		my $i;
		for($i=1;$i<=$parameterId;$i++) {
			my $item = $client->param('sqlplaylist_mixparameter_'.$i);
			$nextParameter{'sqlplaylist_mixparameter_'.$i} = $item;
		}
		Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.SQLPlayList.ChooseParameters',\%nextParameter);
	}else {
		for(my $i=1;$i<=$parameterId;$i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $client->param('sqlplaylist_mixparameter_'.$i)->{'id'};
		}
		handlePlayOrAdd($client, $playlist->{'id'}, $addOnly);
		for(my $i=1;$i<=$parameterId;$i++) {
			Slim::Buttons::Common::popMode($client);
		}
		$client->update();
	}
}
sub requestParametersAndPlayOrAdd {
	my $client = shift;
	my $item = shift;
	my $addOnly = shift;
	my $parameter1 = shift;

	my %nextParameter = (
		'sqlplaylist_nextparameter' => 1,
		'sqlplaylist_selectedplaylist' => $item,
		'sqlplaylist_addonly' => $addOnly
	);
	if(defined($parameter1)) {
		$nextParameter{'sqlplaylist_nextparameter'}=2;
		$nextParameter{'sqlplaylist_mixparameter_1'}=$parameter1;
		debugMsg("Setting parameter 1 = ".$parameter1->{'name'}."(".$parameter1->{'id'}.")\n");
	}
	if(defined($item->{'parameters'}) && defined($item->{'parameters'}->{$nextParameter{'sqlplaylist_nextparameter'}})) {
		Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.SQLPlayList.ChooseParameters',\%nextParameter);
	}else {
		if($nextParameter{'sqlplaylist_nextparameter'}>1) {
			$item->{'parameters'}->{'1'}->{'value'} = $parameter1->{'id'};
		}
		handlePlayOrAdd($client, $item->{'id'}, $addOnly);
		for(my $i=1;$i<$nextParameter{'sqlplaylist_nextparameter'};$i++) {
			Slim::Buttons::Common::popMode($client);
		}
		$client->update();
	}
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my @listRef = ();
	initPlayLists();
	my $playlisttype = $client->param('playlisttype');
	foreach my $pk (sort keys %$playLists) {
		my $playlist = $playLists->{$pk};
		if(!defined($playlisttype)) {
			push @listRef, $playlist;
		}else {
			if(defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && $playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype) {
				debugMsg("Adding ".$playlist->{'name'}."\n");
				push @listRef, $playlist;
			}
		}
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_SQLPLAYLIST} {count}',
		listRef    => \@listRef,
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'PLUGIN.SQLPlayList',
		onPlay     => sub {
			my ($client, $item) = @_;
			if(defined($item->{'parameters'})) {
				requestParametersAndPlayOrAdd($client,$item,0,$client->param('sqlplaylist_mixparameter_1'));
			}else {
				handlePlayOrAdd($client, $item->{'id'}, 0);		
			}
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			if(defined($item->{'parameters'})) {
				requestParametersAndPlayOrAdd($client,$item,1,$client->param('sqlplaylist_mixparameter_1'));
			}else {
				handlePlayOrAdd($client, $item->{'id'}, 1);
			}
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if($item->{'id'} eq 'disable') {
				handlePlayOrAdd($client, $item->{'id'}, 0);
			}elsif(defined($item->{'parameters'})) {
				requestParametersAndPlayOrAdd($client,$item,0,$client->param('sqlplaylist_mixparameter_1'));
			}else {
				$client->bumpRight();
			}
		},
	);
	if(defined($client->param('sqlplaylist_mixparameter_1'))) {
		$params{'sqlplaylist_mixparameter_1'} = $client->param('sqlplaylist_mixparameter_1');
	}

	my $currentPlaying = getCurrentPlayList($client);

	# if we have an active mode, temporarily add the disable option to the list.
	if ($currentPlaying) {
		push @{$params{listRef}},\%disable;
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub initPlugin {
	my $class = shift;
	checkDefaults();
	Slim::Buttons::Common::addMode('PLUGIN.SQLPlayList.ChooseParameters', getFunctions(), \&setChooseParametersMode);
	Slim::Buttons::Common::addMode('PLUGIN.SQLPlayList', getFunctions(), \&setMode);
	if(Slim::Utils::Prefs::get("plugin_sqlplaylist_web_show_mixerlinks")) {
		if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
			Slim::Music::Import::addImporter($class,'SQLPLAYLIST', {
				'mixer'     => \&mixerFunction,
	            'mixerlink' => \&mixerlink});
	    	Slim::Music::Import::useImporter($class, 1);
	    }else {
			Slim::Music::Import::addImporter('SQLPLAYLIST', {
				'mixer'     => \&mixerFunction,
	            'mixerlink' => \&mixerlink});
	    	Slim::Music::Import::useImporter('SQLPLAYLIST', 1);
	    }
	}
}

sub mixerlink {
    my $item = shift;
    my $form = shift;
    my $descend = shift;
#		debugMsg("***********************************\n");
#		for my $it (keys %$form) {
#			debugMsg("form{$it}=".$form->{$it}."\n");
#		}
#		debugMsg("***********************************\n");
	
	my $levelName = $form->{'levelName'};
	if(!$playListTypes) {
		initPlayListTypes();
	}
	if($form->{'noSQLPlayListButton'}) {
		if ($::VERSION lt '6.5') {
    		Slim::Web::Pages::addLinks("mixer", {'SQLPLAYLIST' => undef});
    	}
	}elsif(defined($levelName) && ($levelName eq 'artist' || $levelName eq 'contributor' || $levelName eq 'album' || $levelName eq 'genre')) {
		if($levelName eq 'contributor') {
			$levelName = 'artist';
		}
		if($playListTypes->{$levelName}) {
			$form->{'sqlplaylist_playlisttype'} = $levelName;
			if ($::VERSION ge '6.5') {
	        	$form->{'mixerlinks'}{'SQLPLAYLIST'} = "plugins/SQLPlayList/mixerlink65.html";
	        }else {
	    			Slim::Web::Pages::addLinks("mixer", {'SQLPLAYLIST' => "plugins/SQLPlayList/mixerlink.html"}, 1);
	        }
	    }else {
	    	if ($::VERSION lt '6.5') {
	    		Slim::Web::Pages::addLinks("mixer", {'SQLPLAYLIST' => undef});
	    	}
	    }
    }elsif(defined($levelName) && $levelName eq 'year') {
		$form->{'sqlplaylist_playlisttype'} = $levelName;
    	$form->{'yearid'} = $item->year;
    	if(defined($form->{'yearid'})) {
			if($playListTypes->{$levelName}) {
				if ($::VERSION ge '6.5') {
	    			$form->{'mixerlinks'}{'SQLPlayList'} = "plugins/SQLPlayList/mixerlink65.html";
	    		}else {
	    			Slim::Web::Pages::addLinks("mixer", {'SQLPlayList' => "plugins/SQLPlayList/mixerlink.html"}, 1);
	    		}
		    }else {
		    	if ($::VERSION lt '6.5') {
		    		Slim::Web::Pages::addLinks("mixer", {'SQLPLAYLIST' => undef});
		    	}
		    }
    	}
    }else {
    	my $attributes = $form->{'attributes'};
		my $album;
		if(defined($form->{'levelName'}) && $form->{'levelName'} eq 'age') {
			$album = $item;
		}
		if(defined($album)) {
			$form->{'sqlplaylist_playlisttype'} = 'album';
			$form->{'albumid'} = $album->id;
		}
    	
    	if(defined($form->{'albumid'})) {
			if($playListTypes->{$form->{'sqlplaylist_playlisttype'}}) {
				if ($::VERSION ge '6.5') {
	    			$form->{'mixerlinks'}{'SQLPLAYLIST'} = "plugins/SQLPlayList/mixerlink65.html";
	    		}else {
	    			Slim::Web::Pages::addLinks("mixer", {'SQLPLAYLIST' => "plugins/SQLPlayList/mixerlink.html"}, 1);
	    		}
	    	}else {
		    	if ($::VERSION lt '6.5') {
		    		Slim::Web::Pages::addLinks("mixer", {'SQLPLAYLIST' => undef});
		    	}
	    	}
    	}
    }
    return $form;
}

sub mixerFunction {
	my ($client, $noSettings) = @_;
	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->param('parentParams') ? $client->param('parentParams') : $client->modeParameterStack(-1);
	if(defined($paramref)) {
		if(!$playListTypes) {
			initPlayListTypes();
		}

		my $listIndex = $paramref->{'listIndex'};
		my $items     = $paramref->{'listRef'};
		my $currentItem = $items->[$listIndex];
		my $hierarchy = $paramref->{'hierarchy'};
		my @levels    = split(",", $hierarchy);
		my $level     = $paramref->{'level'} || 0;
		if($playListTypes->{$levels[$level]}) { 
			if($levels[$level] eq 'album' || $levels[$level] eq 'age') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->title
				);
				my %params = (
					'sqlplaylist_mixparameter_1' => \%p,
					'playlisttype' => 'album'
				);
				debugMsg("Calling album playlists with ".$params{'sqlplaylist_mixparameter_1'}->{'name'}."(".$params{'sqlplaylist_mixparameter_1'}->{'id'}.")\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.SQLPlayList',\%params);
				$client->update();
			}elsif($levels[$level] eq 'year') {
				my %p = (
					'id' => $currentItem,
					'name' => $currentItem
				);
				my %params = (
					'sqlplaylist_mixparameter_1' => \%p,
					'playlisttype' => 'year'
				);
				debugMsg("Calling year playlists with ".$params{'sqlplaylist_mixparameter_1'}->{'name'}."(".$params{'sqlplaylist_mixparameter_1'}->{'id'}.")\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.SQLPlayList',\%params);
				$client->update();
			}elsif($levels[$level] eq 'artist') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->name
				);
				my %params = (
					'sqlplaylist_mixparameter_1' => \%p,
					'playlisttype' => 'artist'
				);
				debugMsg("Calling artist playlists with ".$params{'sqlplaylist_mixparameter_1'}->{'name'}."(".$params{'sqlplaylist_mixparameter_1'}->{'id'}.")\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.SQLPlayList',\%params);
				$client->update();
			}elsif($levels[$level] eq 'genre') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->name
				);
				my %params = (
					'sqlplaylist_mixparameter_1' => \%p,
					'playlisttype' => 'genre'
				);
				debugMsg("Calling album playlists with ".$params{'sqlplaylist_mixparameter_1'}->{'name'}."(".$params{'sqlplaylist_mixparameter_1'}->{'id'}.")\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.SQLPlayList',\%params);
				$client->update();
			}else {
				debugMsg("Unknown playlisttype = ".$levels[$level]."\n");
			}
		}else {
			debugMsg("No playlist found for ".$levels[$level]."\n");
		}
	}else {
		debugMsg("No parent parameter found\n");
	}

}

sub webPages {

	my %pages = (
		"sqlplaylist_list\.(?:htm|xml)"     => \&handleWebList,
		"sqlplaylist_mix\.(?:htm|xml)"      => \&handleWebMix,
		"sqlplaylist_mixparameters\.(?:htm|xml)"      => \&handleWebMixParameters,
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
	my $localPlayLists = ();
	if(defined($params->{'playlisttype'})) {
		my %tempPlayLists;
		for my $pk (keys %$playLists) {
			my $pl = $playLists->{$pk};
			if(defined($pl->{'parameters'}) && defined($pl->{'parameters'}->{'1'}) && $pl->{'parameters'}->{'1'}->{'type'} eq $params->{'playlisttype'}) {
				$tempPlayLists{$pk} = $playLists->{$pk};
			}
		}
		$localPlayLists = \%tempPlayLists;
		my $parameter1 = $params->{'sqlplaylist_mixparameter_1'};
		if(defined($parameter1)) {
			if($params->{'playlisttype'} eq 'album') {
				my $album = objectForId('album',$parameter1);
				if(defined($album)) {
					$params->{'pluginSQLPlayListContextName'} = $album->title;
				}
			}elsif($params->{'playlisttype'} eq 'artist') {
				my $artist = objectForId('artist',$parameter1);
				if(defined($artist)) {
					$params->{'pluginSQLPlayListContextName'} = $artist->name;
				}
			}elsif($params->{'playlisttype'} eq 'genre') {
				my $genre = objectForId('genre',$parameter1);
				if(defined($genre)) {
					$params->{'pluginSQLPlayListContextName'} = $genre->name;
				}
			}elsif($params->{'playlisttype'} eq 'year') {
				$params->{'pluginSQLPlayListContextName'} = $parameter1;
			}
		}
	}else {
		$localPlayLists = $playLists;
	}
	$params->{'pluginSQLPlayListPlayLists'} = $localPlayLists;
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
		my $sql = createSQL(Slim::Utils::Unicode::utf8decode($params->{'text'},'utf8'));
		if($sql) {
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

	if($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginSQLPlayListError'} = $sqlerrors;
	}else {
		$params->{'pluginSQLPlayListError'} = undef;
	}
	if ($::VERSION ge '6.5') {
		$params->{'pluginSQLPlayListSlimserver65'} = 1;
	}
}

# Returns a hash whose keys are the genres in the db
sub getGenres {
	my ($client) = @_;
	my %clientGenres = ();

	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
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
	
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
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
	my $minLengthValue = $params->{'mintracklength'};
	my $maxYear = $params->{'maxtrackyear'};
	my $minYear = $params->{'mintrackyear'};
	my $notRepeat = $params->{'notrepeat'};
	debugMsg("Genres = ".$genreListString."\n");
	debugMsg("Artists = ".$artistListString."\n");
	if($params->{'type'} eq "random") {
		my $sql = "select tracks.url from tracks";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
		}
		if($maxLengthValue>0) {
			if($notRepeat) {
				$sql .= " and\n\t";
			}else {
				$sql .= "\n\twhere ";
			}
			$sql .= "tracks.secs<$maxLengthValue";
		}
		if($minLengthValue>0) {
			if($maxLengthValue>0 || $notRepeat) {
				$sql .= " and \n\t"; 
			}else {
				$sql .= "\n\twhere ";
			}
			$sql .= "tracks.secs>$minLengthValue";
		}
		if($maxYear>0) {
			if($maxLengthValue>0 || $minLengthValue>0 || $notRepeat) {
				$sql .= " and \n\t"; 
			}else {
				$sql .= "\n\twhere ";
			}
			$sql .= "tracks.year<=$maxYear";
		}
		if($minYear>0) {
			if($maxLengthValue>0 || $minLengthValue>0 || $maxYear>0 || $notRepeat) {
				$sql .= " and \n\t"; 
			}else {
				$sql .= "\n\twhere ";
			}
			$sql .= "tracks.year>=$minYear";
		}
		$sql .= "\norder by $orderBy limit 10;";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "includinggenres") {
		my $sql = "select tracks.url from tracks \n\tjoin genre_track on\n\t\ttracks.id=genre_track.track\n\tjoin genres on\n\t\tgenre_track.genre=genres.id";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "tracks.audio=1";
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
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "includinggenresincludingartists") {
		my $sql = "select tracks.url from tracks\n\tjoin genre_track on\n\t\ttracks.id=genre_track.track\n\tjoin genres on\n\t\tgenre_track.genre=genres.id\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin contributors on\n\t\tcontributor_track.contributor=contributors.id";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "tracks.audio=1";
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
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "includingartists") {
		my $sql = "select tracks.url from tracks\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin contributors on\n\t\tcontributor_track.contributor=contributors.id";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "tracks.audio=1";
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
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedincludinggenres") {
		my $sql = "select tracks.url from tracks\n\tjoin genre_track on\n\t\ttracks.id=genre_track.track\n\tjoin genres on\n\t\tgenre_track.genre=genres.id\n\tjoin track_statistics on\n\t\ttracks.url=track_statistics.url";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80 and\n\t\ttracks.audio=1";
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
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedincludingartists") {
		my $sql = "select tracks.url from tracks\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin contributors on\n\t\tcontributor_track.contributor=contributors.id\n\tjoin track_statistics on\n\t\ttracks.url=track_statistics.url";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80 and\n\t\ttracks.audio=1";
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
		$sql .= "\n\t order by $orderBy limit 10;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedincludinggenresincludingartists") {
		my $sql = "select tracks.url from tracks\n\tjoin genre_track on\n\t\ttracks.id=genre_track.track\n\tjoin genres on\n\t\tgenre_track.genre=genres.id\n\tjoin contributor_track on\n\t\ttracks.id=contributor_track.track\n\tjoin contributors on\n\t\tcontributor_track.contributor=contributors.id\n\tjoin track_statistics on \n\t\ttracks.url=track_statistics.url";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80 and\n\t\ttracks.audio=1";
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
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludingartists") {
		my $sql = "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect distinct contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks \n\tleft join contributor_track_withname on \n\t\ttracks.id=contributor_track_withname.track";
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
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenresexcludingartists") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect distinct contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
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
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenressqlite") {
		my $sql = "select tracks.url from tracks";
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
		$sql .= "\n\t\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
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
		$sql .= "\n\t\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "excludinggenresexcludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
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
		$sql .= "\n\t\torder by $orderBy limit 10;\n\n";
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
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludingartists") {
		my $sql = "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect distinct contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
		$sql .= "select distinct tracks.url from tracks \n\tleft join contributor_track_withname on \n\t\ttracks.id=contributor_track_withname.track";
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
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenresexcludingartists") {
		my $sql = "create temporary table genre_track_withname \n\t(primary key (track,genre)) \n\tselect genre_track.track,genre_track.genre,genres.name,genres.namesort \n\t\tfrom genre_track,genres \n\t\twhere genre_track.genre=genres.id;\n\n";
		$sql .= "create temporary table contributor_track_withname \n\t(primary key (track,contributor)) \n\tselect distinct contributor_track.track,contributor_track.contributor,contributors.name,contributors.namesort \n\t\tfrom contributor_track,contributors \n\t\twhere contributor_track.contributor=contributors.id;\n\n";
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
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$sql .= "drop temporary table contributor_track_withname;\n";
		$sql .= "drop temporary table genre_track_withname;\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenressqlite") {
		my $sql = "select tracks.url from tracks";
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
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
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
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "topratedexcludinggenresexcludingartistssqlite") {
		my $sql = "select tracks.url from tracks";
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
		$sql .= "\n\torder by $orderBy limit 10;\n\n";
		$params->{'pluginSQLPlayListEditPlayListText'} = $sql;
	}elsif($params->{'type'} eq "toprated") {
		my $sql = "select tracks.url from tracks\n\tjoin track_statistics on\n\t\ttracks.url = track_statistics.url";
		if($notRepeat) {
			$sql .= "\n\tleft join dynamicplaylist_history on\n\t\ttracks.id=dynamicplaylist_history.id";
			$sql .= "\n\twhere dynamicplaylist_history.id is null";
			$sql .= " and\n\t\t";
		}else {
			$sql .= "\n\twhere ";
		}
		$sql .= "track_statistics.rating>=80";
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
		$sql .= "\n\torder by $orderBy limit 10;\n";
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
		my $playlist = getPlayList($client,$params->{'type'});
		if(!defined($playlist)) {
			debugMsg("Playlist not found received:"..$params->{'type'}."\n");
			foreach my $p (keys %$playLists) {
				debugMsg("Got: $p\n");
			}
		}
		if(defined($playlist->{'parameters'})) {
			return handleWebMixParameters($client,$params);
		}else {
			handlePlayOrAdd($client, $params->{'type'}, $params->{'addOnly'});
		}
	}
	return handleWebList($client, $params);
}

sub handleWebMixParameters {
	my ($client,$params) = @_;
	debugMsg("Entering handleWebMixParameters\n");
	my $parameterId = 1;
	my @parameters = ();
	my $playlist = getPlayList($client,$params->{'type'});
	
	for (my $i=1;$i<10;$i++) {
		if(defined($params->{'sqlplaylist_mixparameter_'.$i})) {
			$parameterId = $parameterId +1;
			my %value = (
				'id' => $params->{'sqlplaylist_mixparameter_'.$i}
			);
			$client->param('sqlplaylist_mixparameter_'.$i,\%value);
			debugMsg("Storing parameter $i=".$value{'id'}."\n");
		}
		if($params->{'changedParameter'} eq $i) {
			$i=10;
		}
	}
	if(defined($playlist->{'parameters'}->{$parameterId})) {
		for(my $i=1;$i<$parameterId;$i++) {
			my @parameterValues = ();
			my $parameter = $playlist->{'parameters'}->{$i};
			addParameterValues($client,\@parameterValues,$parameter);
			my %webParameter = (
				'parameter' => $parameter,
				'values' => \@parameterValues,
				'value' => $params->{'sqlplaylist_mixparameter_'.$i}
			);
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
		$params->{'pluginSQLPlayListPlaylist'} = $playlist;
		$params->{'pluginSQLPlayListAddOnly'} = $params->{'addOnly'};
		$params->{'pluginSQLPlayListMixParameters'} = \@parameters;
		my $currentPlaylistId = getCurrentPlayList($client);
		if(defined($currentPlaylistId)) {
			debugMsg("Setting current playlist id to ".$currentPlaylistId."\n");
			my $currentPlaylist = getPlayList($client,$currentPlaylistId);
			if(defined($currentPlaylist)) {
				debugMsg("Setting current playlist to ".$currentPlaylist->{'name'}."\n");
				$params->{'pluginSQLPlayListNowPlaying'} = $currentPlaylist->{'name'};
			}
		}
		if ($::VERSION ge '6.5') {
			$params->{'pluginSQLPlayListSlimserver65'} = 1;
		}
		debugMsg("Exiting handleWebMixParameters\n");
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_mixparameters.html', $params);
	}else {
		for(my $i=1;$i<$parameterId;$i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $client->param('sqlplaylist_mixparameter_'.$i)->{'id'};
		}
		handlePlayOrAdd($client, $params->{'type'}, $params->{'addOnly'});
		debugMsg("Exiting handleWebMixParameters\n");
		return handleWebList($client,$params);
	}
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
	# enable mixer links by default
	if(!defined(Slim::Utils::Prefs::get("plugin_sqlplaylist_web_show_mixerlinks"))) {
		# Default to show mixer links
		debugMsg("Defaulting plugin_sqlplaylist_web_show_mixerlinks to 1\n");
		Slim::Utils::Prefs::set("plugin_sqlplaylist_web_show_mixerlinks",1);
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_sqlplaylist_playlist_directory','plugin_sqlplaylist_showmessages','plugin_sqlplaylist_web_show_mixerlinks'],
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
	plugin_sqlplaylist_web_show_mixerlinks => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_SQLPLAYLIST_WEB_SHOW_MIXERLINKS')
			,'changeIntro' => string('PLUGIN_SQLPLAYLIST_WEB_SHOW_MIXERLINKS')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_sqlplaylist_web_show_mixerlinks"); }
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

sub getTracksForPlaylist {
	my $client = shift;
	my $playlist = shift;
	my $limit = shift;
	my $sqlstatements = $playlist->{'sql'};
	my $dbh = getCurrentDBH();
	if(defined($playlist->{'parameters'})) {
		my $parameters = $playlist->{'parameters'};
		foreach my $i (keys %$parameters) {
			my $value = $parameters->{$i}->{'value'};
			my $parameterid = "\'PlaylistParameter".$parameters->{$i}->{'id'}."\'";
			debugMsg("Replacing ".$parameterid." with ".$value."\n");
			$sqlstatements =~ s/$parameterid/$value/g;
		}
	}
	my $result= executeSQLForPlaylist($sqlstatements,$limit);
	
	return $result;
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
sub startDynamicPlaylist {
	my $client = shift;
	my $item = shift;
	my $params = shift;
	
	my $playlist = getPlayList($client,$item->{'id'});
	requestParametersAndPlayOrAdd($client,$playlist,$params->{'addonly'},undef);
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
			$currentResult{'startfunction'} = \&startDynamicPlaylist,
			$currentResult{'playurl'} = "plugins/SQLPlayList/sqlplaylist_mix.html?type=".escape($playlist)."&addOnly=0";
			$currentResult{'addurl'} = "plugins/SQLPlayList/sqlplaylist_mix.html?type=".escape($playlist)."&addOnly=1";
		}
		if($current->{'groups'} && scalar($current->{'groups'})>0) {
			$currentResult{'groups'} = $current->{'groups'};
		}
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

sub objectForId {
	my $type = shift;
	my $id = shift;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		if($type eq 'artist') {
			$type = 'Contributor';
		}elsif($type eq 'album') {
			$type = 'Album';
		}elsif($type eq 'genre') {
			$type = 'Genre';
		}elsif($type eq 'track') {
			$type = 'Track';
		}elsif($type eq 'playlist') {
			$type = 'Playlist';
		}
		return Slim::Schema->resultset($type)->find($id);
	}else {
		if($type eq 'playlist') {
			$type = 'track';
		}
		return getCurrentDS()->objectForId($type,$id);
	}
}

sub objectForUrl {
	my $url = shift;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return Slim::Schema->objectForUrl({
			'url' => $url
		});
	}else {
		return getCurrentDS()->objectForUrl($url,undef,undef,1);
	}
}

sub getCurrentDBH {
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return Slim::Schema->storage->dbh();
	}else {
		return Slim::Music::Info::getCurrentDataStore()->dbh();
	}
}

sub getCurrentDS {
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
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
	
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
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
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
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
SQLPLAYLIST
	EN	SQL Playlist

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

PLUGIN_SQLPLAYLIST_WEB_SHOW_MIXERLINKS
	EN	Show SQLPlayList button in browse pages

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

PLUGIN_SQLPLAYLIST_MIXPARAMETERS_TITLE
	EN	Enter additional parameters for playlist
EOF

}

1;

__END__
