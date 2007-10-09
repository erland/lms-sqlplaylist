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

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use XML::Simple;
use Data::Dumper;
use HTML::Entities;
use FindBin qw($Bin);
use SOAP::Lite;
use Plugins::SQLPlayList::Settings;

use Plugins::SQLPlayList::ConfigManager::Main;

use Slim::Schema;

# Information on each clients sqlplaylist
my $playLists = undef;
my $playListTypes = undef;
my $sqlerrors = '';
my $PLUGINVERSION = undef;

my $configManager = undef;

my %disable = (
	'id' => 'disable', 
	'file' => '', 
	'name' => '', 
	'sql' => '', 
	'fulltext' => ''
);

my $prefs = preferences('plugin.sqlplaylist');
my $multiLibraryPrefs = preferences('plugin.multilibrary');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.sqlplaylist',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_SQLPLAYLIST',
});

$prefs->migrate(1, sub {
	$prefs->set('playlist_directory', Slim::Utils::Prefs::OldPrefs->get('plugin_sqlplaylist_playlist_directory') || $serverPrefs->get('playlistdir')  );
	$prefs->set('template_directory',  Slim::Utils::Prefs::OldPrefs->get('plugin_sqlplaylist_template_directory')   || ''  );
	$prefs->set('download_url',  Slim::Utils::Prefs::OldPrefs->get('plugin_sqlplaylist_download_url')   || 'http://erland.homeip.net/datacollection/services/DataCollection'  );
	1;
});
	
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
	$log->debug("".($add ? 'Add' : 'Play')."$item\n");
	
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
	# indicate request source
	$request->source('PLUGIN_SQLPLAYLIST');
}

sub getPlayList {
	my $client = shift;
	my $type = shift;
	
	return undef unless $type;

	$log->debug("Get playlist: $type\n");
	if(!$playLists) {
		initPlayLists($client);
	}
	return undef unless $playLists;
	
	return $playLists->{$type};
}
sub initPlayListTypes {
	my $client = shift;
	if(!$playLists) {
		initPlayLists($client);
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
	my $client = shift;
	my @pluginDirs = ();

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1);

	$playLists = $itemConfiguration->{'playlists'};
	initPlayListTypes($client);
	if(defined($client)) {
		# We need to make sure the playlists in DynamicPlayList plugin is re-read
		my $request = $client->execute(['dynamicplaylist', 'playlists']);
		# indicate request source
		$request->source('PLUGIN_SQLPLAYLIST');
	}
}


sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	checkDefaults();
	Plugins::SQLPlayList::Settings->new($class);
}

sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'pluginPrefs' => $prefs,
			'logHandler' => $log,
			'pluginId' => 'SQLPlayList',
			'pluginVersion' => $PLUGINVERSION,
			'downloadApplicationId' => 'SQLPlayList',
			'addSqlErrorCallback' => \&addSQLError
		);
		$configManager = Plugins::SQLPlayList::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}


sub webPages {

	my %pages = (
		"SQLPlayList/sqlplaylist_list\.(?:htm|xml)"     => \&handleWebList,
		"SQLPlayList/webadminmethods_edititem\.(?:htm|xml)"      => \&handleWebEditPlaylist,
		"SQLPlayList/webadminmethods_newitemtypes\.(?:htm|xml)"      => \&handleWebNewPlaylistTypes,
		"SQLPlayList/webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeletePlaylistType,
                "SQLPlayList/webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewPlaylistParameters,
		"SQLPlayList/webadminmethods_newitem\.(?:htm|xml)"      => \&handleWebNewPlaylist,
		"SQLPlayList/webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"SQLPlayList/webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewPlaylists,
		"SQLPlayList/webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadPlaylists,
		"SQLPlayList/webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadPlaylist,
		"SQLPlayList/webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishPlaylistParameters,
		"SQLPlayList/webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishPlaylist,
                "SQLPlayList/webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimplePlaylist,
                "SQLPlayList/webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimplePlaylist,
		"SQLPlayList/webadminmethods_saveitem\.(?:htm|xml)"      => \&handleWebSavePlaylist,
		"SQLPlayList/webadminmethods_savenewitem\.(?:htm|xml)"      => \&handleWebSaveNewPlaylist,
		"SQLPlayList/webadminmethods_removeitem\.(?:htm|xml)"      => \&handleWebRemovePlaylist,
	);

	for my $page (keys %pages) {
		Slim::Web::HTTP::addPageFunction($page, $pages{$page});
	}

	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_SQLPLAYLIST' => 'plugins/SQLPlayList/sqlplaylist_list.html' });

	#Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_SQLPLAYLIST' => 'plugins/SQLPlayList/sqlplaylist_list.html' });
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;
	
	my $playlist = undef;
	if($params->{'play'}) {
		my $playlistId = $params->{'file'};
		$playlistId =~ s/\.sql\.xml$//;
		$playlistId =~ s/\.sql\.values\.xml$//;
		$playlist = getPlayList($client,escape($playlistId,"^A-Za-z0-9\-_"));
		handlePlayOrAdd($client, $playlist->{'id'});
	}

	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_redirect.html', $params);
	}elsif($params->{'reload'}) { 	
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_reload.html', $params);
	}

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		if(defined($params->{'cleancache'}) && $params->{'cleancache'}) {
			my $cache = Slim::Utils::Cache->new("FileCache/SQLPlayList");
			$cache->clear();
		}
		initPlayLists($client);
	}
	my $currentPlaying = eval { Plugins::DynamicPlayList::Plugin::getCurrentPlayList($client) };
	if ($@) {
		warn("SQLPlayList: Error getting current playlist from DynamicPlayList plugin: $@\n");
	}
	if($currentPlaying) {
		$currentPlaying =~ s/^sqlplaylist_//;
	}
	if(!defined($playlist)) {
		$playlist = getPlayList($client,$currentPlaying);
	}
	my $name = undef;
	if($playlist) {
		$name = $playlist->{'name'};
	}
	my $templateDir = $prefs->get('template_directory');
	if(!defined($templateDir) || !-d $templateDir) {
		$params->{'pluginSQLPlayListDownloadMessage'} = 'You have to specify a template directory before you can download playlists';
	}
	my @webPlaylists = ();
	for my $key (keys %$playLists) {
		push @webPlaylists,$playLists->{$key};
	}
	my @webPlaylists = sort { uc($a->{'name'}) cmp uc($b->{'name'}) } @webPlaylists;

	$params->{'pluginSQLPlayListPlayLists'} = \@webPlaylists;
	$params->{'pluginSQLPlayListNowPlaying'} = $name;
	if(!UNIVERSAL::can("Plugins::DynamicPlayList::Plugin","getCurrentPlayList")) {
		$params->{'pluginSQLPlayListError'} = "ERROR!!! Cannot find DynamicPlayList plugin, please make sure you have installed and enabled at least DynamicPlayList 1.3"
	}
	$params->{'pluginSQLPlayListVersion'} = $PLUGINVERSION;
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_list.html', $params);
}

sub isPluginsInstalled {
	my $client = shift;
	my $pluginList = shift;
	my $enabledPlugin = 1;
	foreach my $plugin (split /,/, $pluginList) {
		if($enabledPlugin) {
			$enabledPlugin = grep(/$plugin/, Slim::Utils::PluginManager->enabledPlugins($client));
		}
	}
	return $enabledPlugin;
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
	
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/webadminmethods_newitem.html', $params);
}

# Draws the plugin's edit playlist web page
sub handleWebTestEditPlaylist {
	my ($client, $params) = @_;

	handleWebTestPlaylist($client,$params);
	
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/webadminmethods_edititem.html', $params);
}

sub handleWebTestPlaylist {
	my ($client, $params) = @_;
	if(defined($params->{'deletesimple'})) {
		$params->{'pluginWebAdminMethodsEditItemDeleteSimple'} = $params->{'deletesimple'};
	}
	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = 1;
	}
	$params->{'pluginWebAdminMethodsEditItemFile'} = $params->{'file'};
	$params->{'pluginWebAdminMethodsEditItemData'} = $params->{'text'};
	$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($params->{'file'});
	if($params->{'text'}) {
		my $playlist = createSQLPlayList($client,$params->{'text'});
		if($playlist) {
			if(handleWebTestParameters($client,$params,$playlist)) {
				my $sql = $playlist->{'sql'};
				if(defined($playlist->{'parameters'})) {
					$sql = replaceParametersInSQL($sql,$playlist->{'parameters'});
				}
				$sql = replaceParametersInSQL($sql,getInternalParameters($client,100,0),'Playlist');
				my $tracks = executeSQLForPlaylist($sql,undef,$playlist);
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
		$params->{'pluginWebAdminMethodsError'} = $sqlerrors;
	}else {
		$params->{'pluginWebAdminMethodsError'} = undef;
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
		$log->debug("Getting values for: ".$parameter->{'name'}."\n");
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
	
	$log->debug("Getting values for ".$parameter->{'name'}." of type ".$parameter->{'type'}."\n");
	my $sql = undef;
	if(lc($parameter->{'type'}) eq 'album') {
		$sql = "select id,title from albums order by titlesort";
	}elsif(lc($parameter->{'type'}) eq 'artist') {
		$sql = "select id,name from contributors where namesort is not null order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'genre') {
		$sql = "select id,name from genres order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'year') {
		$sql = "select year,year from tracks where year is not null group by year order by year desc";
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
				$log->warn("Error, invalid parameter value: $value\n");
			}
		}
	}elsif(lc($parameter->{'type'}) eq 'custom') {
		if(defined($parameter->{'definition'}) && lc($parameter->{'definition'}) =~ /^select/ ) {
			$sql = $parameter->{'definition'};
			for (my $i=1;$i<$parameter->{'id'};$i++) {
				my $parameter = $client->param('sqlplaylist_parameter_'.$i);
				my $value = $parameter->{'id'};
				my $parameterid = "\'PlaylistParameter".$i."\'";
				$log->debug("Replacing ".$parameterid." with ".$value."\n");
				$sql =~ s/$parameterid/$value/g;
			}
		}
	}
	
	if(defined($sql)) {
		my $dbh = getCurrentDBH();
    	eval {
			my $sth = $dbh->prepare( $sql );
			$log->debug("Executing value list: $sql\n");
			$sth->execute() or do {
	            $log->warn("Error executing: $sql\n");
	            $sql = undef;
			};
			if(defined($sql)) {
				my $id;
				my $name;
				my $sortlink;
				eval {
					$sth->bind_columns( undef, \$id,\$name,\$sortlink);
				};
				if( $@ ) {
					$sth->bind_columns( undef, \$id,\$name);
				}
				while( $sth->fetch() ) {
					my %listitem = (
						'id' => $id,
						'name' => Slim::Utils::Unicode::utf8decode($name,'utf8')
					);
				  	push @$listRef, \%listitem;
			  	}
			  	$log->debug("Added ".scalar(@$listRef)." items to value list\n");
			}
			$sth->finish();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n$@\n";
		}		
	}
}

sub structurePlaylistTypes {
	my $templates = shift;
	
	my %templatesHash = ();
	
	for my $key (keys %$templates) {
		my $plugin = $templates->{$key}->{'sqlplaylist_plugin'};
		if(defined($templates->{$key}->{'customplaylist'})) {
			$plugin = 'ZZZ';
			if(defined($templates->{$key}->{'downloadsection'})) {
				$plugin .= $templates->{$key}->{'downloadsection'};
			}
		}
		if(!defined($plugin)) {
			$plugin = 'AAA';
		}
		my $array = $templatesHash{$plugin};
		if(!defined($array)) {
			my @newArray = ();
			$array = \@newArray;
			$templatesHash{$plugin} = $array;
		}
		push @$array,$templates->{$key};
	}
	for my $key (keys %templatesHash) {
		my $array = $templatesHash{$key};
		my @sortedArray = sort { uc($a->{'name'}) cmp uc($b->{'name'}) } @$array;
		$templatesHash{$key} = \@sortedArray;
	}
	return \%templatesHash;
}


sub handleWebEditPlaylists {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItems($client,$params);	
}

sub handleWebEditPlaylist {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItem($client,$params);	
}

sub handleWebDeletePlaylistType {
	my ($client, $params) = @_;
	return getConfigManager()->webDeleteItemType($client,$params);	
}

sub handleWebNewPlaylistTypes {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemTypes($client,$params);	
}

sub handleWebNewPlaylistParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemParameters($client,$params);	
}

sub handleWebLogin {
	my ($client, $params) = @_;
	return getConfigManager()->webLogin($client,$params);	
}

sub handleWebPublishPlaylistParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItemParameters($client,$params);	
}

sub handleWebPublishPlaylist {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItem($client,$params);	
}

sub handleWebDownloadPlaylists {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItems($client,$params);	
}

sub handleWebDownloadNewPlaylists {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadNewItems($client,$params);	
}

sub handleWebDownloadPlaylist {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItem($client,$params);	
}

sub handleWebNewPlaylist {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItem($client,$params);	
}

sub handleWebSaveSimplePlaylist {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveSimpleItem($client,$params);	
}

sub handleWebRemovePlaylist {
	my ($client, $params) = @_;
	return getConfigManager()->webRemoveItem($client,$params);	
}

sub handleWebSaveNewSimplePlaylist {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewSimpleItem($client,$params);	
}

sub handleWebSaveNewPlaylist {
	my ($client, $params) = @_;
	if($params->{'testonly'} eq "1") {
		return handleWebTestNewPlaylist($client,$params);
	}
	handleWebTestPlaylist($client,$params);
	$params->{'pluginSQLPlayListTestParameters'} = undef;
	$params->{'pluginSQLPlayListEditPlayListTestResult'} = undef;
	if(!defined($params->{'pluginWebAdminMethodsError'})) {
		return getConfigManager()->webSaveNewItem($client,$params);
	}else {
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/webadminmethods_newitem.html', $params);
	}
}

sub handleWebSavePlaylist {
	my ($client, $params) = @_;
	if($params->{'testonly'} eq "1") {
		return handleWebTestEditPlaylist($client,$params);
	}
	handleWebTestPlaylist($client,$params);
	$params->{'pluginSQLPlayListTestParameters'} = undef;
	$params->{'pluginSQLPlayListEditPlayListTestResult'} = undef;
	if(!defined($params->{'pluginWebAdminMethodsError'})) {
		return getConfigManager()->webSaveItem($client,$params);
	}else {
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/webadminmethods_edititem.html', $params);
	}
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
	my $prefVal = $prefs->get('playlist_directory');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		my $dir=$serverPrefs->get('playlistdir');
		$log->debug("Defaulting plugin_sqlplaylist_playlist_directory to:$dir\n");
		$prefs->set('playlist_directory', $dir);
	}

	$prefVal = $prefs->get('download_url');
	if (! defined $prefVal) {
		# Default to not show debug messages
		$log->debug("Defaulting plugin_sqlplaylist_download_url\n");
		$prefs->set('download_url', 'http://erland.homeip.net/datacollection/services/DataCollection');
	}
}

sub replaceParametersInSQL {
	my $sql = shift;
	my $parameters = shift;
	my $parameterType = shift;
	if(!defined($parameterType)) {
		$parameterType='PlaylistParameter';
	}
	
	if(defined($parameters)) {
		foreach my $key (keys %$parameters) {
			my $parameter = $parameters->{$key};
			my $value = $parameter->{'value'};
			if(!defined($value)) {
				$value='';
			}
			my $parameterid = "\'$parameterType".$parameter->{'id'}."\'";
			$log->debug("Replacing ".$parameterid." with ".$value."\n");
			$sql =~ s/$parameterid/$value/g;
		}
	}
	return $sql;
}
sub getTracksForPlaylist {
	my $client = shift;
	my $playlist = shift;
	my $limit = shift;
	my $offset = shift;
	my $parameters = shift;

	my $sqlstatements = $playlist->{'sql'};
	my $dbh = getCurrentDBH();
	$sqlstatements = replaceParametersInSQL($sqlstatements,$parameters);
	my $offsetLimitParameters = getInternalParameters($client,$limit,$offset);
	$sqlstatements = replaceParametersInSQL($sqlstatements,$offsetLimitParameters,'Playlist');
	my $unlimitedOption = getPlaylistOption($playlist,'Unlimited');
	if($unlimitedOption) {
		$limit = undef;
	}
	my $result= executeSQLForPlaylist($sqlstatements,$limit,$playlist);
	return $result;
}

sub fisher_yates_shuffle {
    my $myarray = shift;  
    my $i = @$myarray;
    if(scalar(@$myarray)>1) {
	    while (--$i) {
	        my $j = int rand ($i+1);
	        @$myarray[$i,$j] = @$myarray[$j,$i];
	    }
    }
}

sub getPlaylistOption {
	my $playlist = shift;
	my $option = shift;

	if(defined($playlist->{'options'})){
		if(defined($playlist->{'options'}->{$option})) {
			return $playlist->{'options'}->{$option}->{'value'};
		}
	}
	return undef;
}
sub getInternalParameters {
	my $client = shift;
	my $limit = shift;
	my $offset = shift;

	my %offsetLimitParameters = ();
	my %offsetParameter = (
		'id' => 'Offset',
		'value' => $offset
	);
	my %limitParameter = (
		'id' => 'Limit',
		'value' => $limit
	);
	my $activeLibrary = 0;
	if(isPluginsInstalled($client,'MultiLibrary::Plugin')) {
		$activeLibrary = $multiLibraryPrefs->client($client)->get('activelibraryno');
		if(!defined($activeLibrary)) {
			$activeLibrary = 0;
		}
	}
	my %activeLibraryParameter = (
		'id' => 'ActiveLibrary',
		'value' => $activeLibrary
	);
	$offsetLimitParameters{'PlaylistActiveLibrary'} = \%activeLibraryParameter;
	$offsetLimitParameters{'PlaylistOffset'} = \%offsetParameter;
	$offsetLimitParameters{'PlaylistLimit'} = \%limitParameter;
	return \%offsetLimitParameters;
}


sub createSQLPlayList {
	my $client = shift;
	my $sqlstatements = shift;
	my %items = ();
	my %localcontext = ();
	my %globalcontext = (
		'source' => 'custom'
	);
	my $playlist = getConfigManager()->contentParser->parseContentImplementation($client,"test",$sqlstatements,\%items,\%globalcontext,\%localcontext);
	return $playlist;
}
sub executeSQLForPlaylist {
	my $sqlstatements = shift;
	my $limit = shift;
	my $playlist = shift;
	my @result;
	my $dbh = getCurrentDBH();
	my $trackno = 0;
	$sqlerrors = "";
	my $contentType = getPlaylistOption($playlist,'ContentType');
	my $hardcodedlimit = getPlaylistOption($playlist,'NoOfTracks');
	if(defined($hardcodedlimit)) {
		$limit = $hardcodedlimit;
	}
	my $noRepeat = getPlaylistOption($playlist,'DontRepeatTracks');
	if(defined($contentType)) {
		$log->debug("Executing SQL for content type: $contentType\n");
	}
	for my $sql (split(/[\n\r]/,$sqlstatements)) {
    		eval {
			my $sth = $dbh->prepare( $sql );
			$log->debug("Executing: $sql\n");
			$sth->execute() or do {
				$log->warn("Error executing: $sql\n");
				$sql = undef;
			};

		        if ($sql =~ /^\(*SELECT+/oi) {
				$log->warn("Executing and collecting: $sql\n");
				my $url;
				$sth->bind_col( 1, \$url);
				while( $sth->fetch() ) {
					my $tracks = getTracksForResult($url,$contentType,$limit,$noRepeat);
				 	for my $track (@$tracks) {
						$trackno++;
						if(!$limit || $trackno<=$limit) {
							$log->debug("Adding: ".($track->url)."\n");
							push @result, $track;
						}
					}
				}
			}
			$sth->finish();
		};
		if( $@ ) {
			$sqlerrors .= $DBI::errstr."<br>$@<br>";
			warn "Database error: $DBI::errstr\n$@\n";
		}		
	}
	return \@result;
}

sub getTracksForResult {
	my $item = shift;
	my $contentType = shift;
	my $limit = shift;
	my $noRepeat = shift;
	my $dbh = getCurrentDBH();
	my @result  = ();
	my $sth = undef;
	my $sql = undef;
	if(!defined($contentType) || $contentType eq 'track' || $contentType eq '') {
		my @resultTracks = ();
		my $track = objectForUrl($item);
		push @result,$track;
	}elsif($contentType eq 'album') {
		if($noRepeat) {
			$sql = "select tracks.id from tracks left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and tracks.album=$item group by tracks.id";
		}else {
			$sql = "select tracks.id from tracks where tracks.album=$item group by tracks.id";
		}
		if($limit) {
			$sql .= " order by rand() limit $limit";
		}else {
			$sql .= " order by disc,tracknum";
		}
	}elsif($contentType eq 'artist') {
		if($noRepeat) {
			$sql = "select tracks.id from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and contributor_track.contributor=$item group by tracks.id";
		}else {
			$sql = "select tracks.id from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) where contributor_track.contributor=$item group by tracks.id";
		}
		if($limit) {
			 $sql .=" order by rand() limit $limit";
		}else {
			$sql .= " order by tracks.album,tracks.disc,tracks.tracknum";
		}
	}elsif($contentType eq 'year') {
		if($noRepeat) {
			$sql = "select tracks.id from tracks left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and tracks.year=$item group by tracks.id";
		}else {
			$sql = "select tracks.id from tracks where tracks.year=$item";
		}
		if($limit) {
			 $sql .=" order by rand() limit $limit";
		}else {
			$sql .= " order by tracks.year desc,tracks.album,tracks.disc,tracks.tracknum";
		}
	}elsif($contentType eq 'genre') {
		if($noRepeat) {
			$sql = "select tracks.id from tracks join genre_track on tracks.id=genre_track.track left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and genre_track.genre=$item group by tracks.id";
		}else {
			$sql = "select tracks.id from tracks join genre_track on tracks.id=genre_track.track where genre_track.genre=$item group by tracks.id";
		}
		if($limit) {
			 $sql .=" order by rand() limit $limit";
		}else {
			$sql .= " order by tracks.album,tracks.disc,tracks.tracknum";
		}
	}elsif($contentType eq 'playlist') {
		if($noRepeat) {
			$sql = "select tracks.id from tracks join playlist_track on tracks.id=playlist_track.track left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and playlist_track.playlist=$item group by tracks.id";
		}else {
			$sql = "select tracks.id from tracks join playlist_track on tracks.id=playlist_track.track where playlist_track.playlist=$item group by tracks.id";
		}
		if($limit) {
			 $sql .=" order by rand() limit $limit";
		}else {
			$sql .= " order by playlist_track.position";
		}
	}
	if($sql) {
		$sth = $dbh->prepare($sql);
		$sth->execute();
		my $trackId;
		$sth->bind_columns(undef,\$trackId);
		my @trackIds = ();
		while( $sth->fetch()) {
			push @trackIds,$trackId;
		}
		$sth->finish();
		my @tmpResult = ();
		if(scalar(@trackIds)>0) {
			@tmpResult = Slim::Schema->rs('Track')->search({ 'id' => { 'in' => \@trackIds } });
		}
		# Sort according to original select
		for my $id (@trackIds) {
			for my $item (@tmpResult) {
				if($item->id eq $id) {
					push @result,$item;
					last;
				}
			}
		}
	}
	return \@result;
}
sub getDynamicPlayLists {
	my ($client) = @_;

	if(!$playLists) {
		initPlayLists($client);
	}
	
	my %result = ();
	
	foreach my $playlist (sort keys %$playLists) {
		my $playlistid = "sqlplaylist_".$playlist;
		my $current = $playLists->{$playlist};
		my %currentResult = (
			'id' => $playlist,
			'name' => $current->{'name'},
			'url' => "plugins/SQLPlayList/webadminmethods_edititem.html?item=".escape($playlist)."&redirect=1"
		);
		if(defined($current->{'parameters'})) {
			my $parameters = $current->{'parameters'};
			foreach my $pk (keys %$parameters) {
				my %parameter = (
					'id' => $pk,
					'type' => $parameters->{$pk}->{'type'},
					'name' => $parameters->{$pk}->{'name'},
					'definition' => $parameters->{$pk}->{'definition'}
				);
				$currentResult{'parameters'}->{$pk} = \%parameter;
			}
		}
		if(defined($current->{'startactions'})) {
			$currentResult{'startactions'}=$current->{'startactions'};
		}
		if(defined($current->{'stopactions'})) {
			$currentResult{'stopactions'}=$current->{'stopactions'};
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
	
	$log->debug("Getting tracks for: ".$dynamicplaylist->{'id'}."\n");
	my $playlist = getPlayList($client,$dynamicplaylist->{'id'});
	my $result = getTracksForPlaylist($client,$playlist,$limit,$offset,$parameters);
	
	return \@{$result};
}


sub objectForId {
	my $type = shift;
	my $id = shift;
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
}

sub objectForUrl {
	my $url = shift;
	return Slim::Schema->objectForUrl({
		'url' => $url
	});
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
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
	
	$item->displayAsHTML($form);
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

1;

__END__
