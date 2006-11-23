1. LICENSE
==========
Copyright (C) 2006 Erland Isaksson (erland_i@hotmail.com)

Portions of code derived from the Random Mix plugin:
Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
New world order by Dan Sully - <dan | at | slimdevices.com>
Fairly substantial rewrite by Max Spicer

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

2. PREREQUISITES
================
- A slimserver 6.5 installed and configured (6.3 might work for some playlists but it has not been tested)
- The DynamicPlayList plugin must installed

3. FILES
========
This archive should contain the following files:
- readme.txt (this file)
- license.txt (the license)
- *.pm (The application itself)

4. INSTALLATION
===============
Unzip to the Plugins directory in the Slimserver installation.

5. USAGE
========
This plugin makes it possible to create smartplaylists based on SQL queries.
The playlists are continous and will run forever in the same way as the Random Mix plugin.

First you will have to configure a SQLPlayList playlist directory in the plugins
section of the slimserver settings web interface. After this is done you are ready to
create your smart playlists as described below.

The easiest way to create a playlist is from the SQLPlayList web userinterface, but you can also create it manually as described below.

To create a playlist manually you:
1. Create a file with .sql extension (The contents is described below)
2. Put the sql file in the configured SQLPlayList playlist directory
3. Navigate to the SQLPlayList plugin menu on the Squeezebox and select the playlist and start playing, or use the SQL PlayList plugin menu in the web interface.

The SQLPlayList sql file for a playlist must have the following syntax:
- First row: The name of the playlist (This text will be shown for the playlist in the Squeezebox menu for SQLPlayList plugin). 
             This first row can also as the examples begin with: -- PlaylistName: 

- Groups row: The groups where the playlist should be in the navigation tree in the DynamicPlayList plugin. For example the following
              will put the playlist both below "Albums/Pop" and "Good playlists":
              -- PlaylistGroups: Albums/Pop,Good playlists

- Parameter rows: The parameters that should be requested from the user, up to 9 parameters are supported. The parameter row are optional, 
                  the id must start with 1 and increase with 1 for each parameter in the playlist. The syntax is:
              -- PlaylistParameter[id]:[type]:[name]:[definition]

              id: A number between 1-9
              type: One of: album,artist,genre,year,playlist,list,custom
              name: The text shown to the user when requesting parameter
              definition: Valid for type=list and type=custom
              type=list: Specify each value separated with : in definition parameter, for each item the value for the
                         parameter is specified first and the value shown to the user next and they are separated with
                         a ,. See examples below.
              type=custom: Specify the SQL which returns parameter value (for parameter) and parameter value (shown to user).
                           See examples below

              Some examples:
              -- PlaylistParameter1:album:Choose album:
              -- PlaylistParameter2:genre:Choose genre:
              -- PlaylistParameter3:year:Choose year:
              -- PlaylistParameter4:playlist:Choose playlist:
              -- PlaylistParameter5:artist:Choose artist:
              -- PlaylistParameter6:list:Choose rating:20:*,40:**,60:***,80:****,100:*****
              -- PlaylistParameter7:custom:Choose artist:select id,name from contributors where name like 'A%'

- Option rows: The options for the playlist, the options described below is currently supported. The option rows are optional.
              -- PlaylistOption [id]:[value]
              
              id: The id of the option
              value: The value of the option

              Currently supported options:
              Unlimited: 1 = Don't limit the returned number of tracks to the requested number from DynamicPlayList plugin
              ContentType: Specifies the type of object the SQL returns, can be one of: track, album, artist, playlist, genre, year
                                   track or not specified: SQL shall return tracks.url
                                   album: SQL shall return albums.id or tracks.album
                                   artist: SQL shall return contributors.id or contributor_track.contributor
                                   genre: SQL shall return genres.id or genre_track.genre
                                   year: SQL shall return tracks.year or years.id
                                   playlist: SQL shall return playlist_track.playlist
              NoOfTracks: Number of tracks that shall be returned i ContentType is one of: album, artist, playlist, genre, year
              DontRepeatTracks: 1 = Do not add tracks already played when ContentType is one of: album, artist, playlist, genre, year

              Some examples:
              -- PlaylistOption Unlimited:1 
              -- PlaylistOption ContentType:album 
              -- PlaylistOption NoOfTracks:10
              -- PlaylistOption DontRepeatTracks:1 

- Other rows: SQL queries, all queries will be executed and those starting with SELECT must return a single "url" column and the 
              tracks returned in all SELECT statements will be part of the playlist.

There are also a number of dynamic parameters which will be replaced every time the SQL statements are executed, the replacements works in the same way as
the PlaylistParameter handling. The follogin Dynamic parameters exist:
              PlaylistLimit: The number of tracks requested from DynamicPlayList plugin
              PlaylistOffset: The number of tracks previously played for this playlist             

Some example playlists follows below, observere that the SQL statements needs to be different for the standard slimserver database in 6.3(SQLite) and
for the MySQL database in slimserver 6.5 and later. So make sure you use the right syntax based on which database you are using. The main difference for simple queries is
that SQLite uses "order by random()" while MySQL uses "order by rand()". See also the playlist templates available in the web ui for more examples.

Playlist1.sql: MySQL (Tracks never played)
-----------------------------------------------
-- PlaylistName: Not played tracks
select url from tracks where audio=1 and playCount is null order by rand() limit 10;

Playlist2.sql: MySQL (Tracks rated as 4-5 in TrackStat, requires TrackStat plugin)
---------------------------------------------------------------------------------
-- PlaylistName: Top rated tracks
-- PlaylistGroups: Top rated
select tracks.url from track_statistics,tracks,albums where tracks.album=albums.id and tracks.url=track_statistics.url and track_statistics.rating>=80 and tracks.audio=1 order by rand() limit 10;

Playlist3.sql: MySQL (All tracks besides those which contains genre=Christmas and some bad albums)
-------------------------------------------------------------------------------------------------
-- PlaylistName: Mixed without Christmas

create temporary table genre_track_withname (primary key (track,genre)) select genre_track.track,genre_track.genre,genres.namesort from genre_track,genres where genre_track.genre=genres.id;
create temporary table tracks_nochristmas (primary key (id)) select distinct tracks.id,tracks.title,tracks.url,tracks.album from tracks left join genre_track_withname on tracks.id=genre_track_withname.track and genre_track_withname.namesort='CHRISTMAS' where genre_track_withname.track is null and tracks.audio=1 order by tracks.title;
create temporary table albums_nobad (primary key (id)) select albums.id from albums,tracks_nochristmas,contributor_track where tracks_nochristmas.album=albums.id and tracks_nochristmas.id=contributor_track.track and albums.title not in ('Music Of The Movies - The Love Songs','Piano moods','Love Themes Of The Pan Pipes') group by (albums.id) having count(distinct contributor_track.contributor)<4 order by id;

select tracks_nochristmas.url from tracks_nochristmas,albums_nobad where tracks_nochristmas.album=albums_nobad.id order by rand() limit 10;

drop temporary table genre_track_withname;
drop temporary table tracks_nochristmas;
drop temporary table albums_nobad;

6. PLUGIN DEVELOPERS
====================
You can implement your own playlist templates by implementing the methods described below
in your plugin. The plugin must be enabled for it to be detected by SQLPlayList plugin.

# Returns an array with templates
# This method will be called by the SQLPlayList plugin whenever the type of playlists available shall be shown
# Parameters in each template
# id = A uniqe identifier 
# type =	
#	final: You are responsible for replacing parameters in getSQLPlayListTemplateData, 
#	template: SQLPlayList will replace [% parametervalue %] with the actual value, same template types as used in the HTML pages 
#                     for slimserver. See also all *.templates files in SQLPlayList/Templates directory for some samples
# template = The actual playlist template configuration, consists of the following parts
#	name = A user friendly name of your playlist type
#	description = A description of your playlist type
#	parameter = An array of playlist parameters that shall be possible for the user to specify, see *.xml files in SQLPlayList/Templates directory
#                          for some samples
sub getSQLPlayListTemplates {
	my ($client) = @_;

	my @result = ();
	my %template = (
		'id' => 'mynicetemplate',
		'type' => 'final',
		'template' => {
			'name' => 'My nice playlist',
			'description' => 'A random playlist with parameter for number of tracks to return',
			'parameter' => [
				{
					'type' => 'text',
					'id' => 'playlistlength',
					'name' => 'Length of playlist',
					'value' => 20
				}
			]
		}
	);
	push @result,\%template;
	return \@result;
}

# Returns the actual playlist for a specified template based on parameter values, this method will be
# called by SQLPlayList plugin when a playlist is required. The returned data is the actual playlist.
# In-parameters:
# template = The template for selected playlist, the same as returned previously by getSQLPlayListTemplates method
# parameters = A hash map with parameter values that the user has entered for your parameters
sub getSQLPlayListTemplateData {
	my ($client,$template,$parameters) = @_;

	if($template->{'id'} eq 'mynicetemplate') {
		if($parameters->{'playlistlength'}) {
			my $result = "-- PlaylistName:My nice playlist\nselect url from tracks order by rand() limit ".$parameters->{'playlistlength'}.";";
			return $result;
		}else {
			my $result = "-- PlaylistName:My nice playlist\nselect url from tracks order by rand() limit 10;";
			return $result;
		}
	}
	return undef;
}
