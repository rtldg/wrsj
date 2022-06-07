/*
 * WRSJ by rtldg
 *
 * Source repo: https://github.com/rtldg/wrsj
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

enum struct WRSJ_RecordInfo {
	int id;
	char name[32+1];
	//char mapname[90]; // longest map name I've seen is bhop_pneumonoultramicroscopicsilicovolcanoconiosis_v3_001.bsp
	char hostname[128];
	char time[32];
	char wrDif[16];
	char steamid[24];
	int accountid;
	int tier;
	char date[32];
	float sync;
	int strafes;
	int jumps;
	char country[33];
}

typeset WRSJ_QueryFinishedFunc
{
	function void (const char map[PLATFORM_MAX_PATH], ArrayList records, any callerdata);
};

/**
 * asdf
 *
 * @param map                       Map name you want to query results for.
 * @param cached_results_okay       Whether returning already-cached results is okay.
 * @return                          Returns true if the http-request library "sent" the request. false if not...
 */
native bool WRSJ_QueryMap(const char[] map, bool cached_results_okay=true);

/*
void QueryFinished(const char map[PLATFORM_MAX_PATH], ArrayList records, any callerdata)
{
	PrintToServer("%s %d %xh", map, records, records?records.Length:-1, callerdata);
	// example output: bhop_badges 42 0x69
}

Action Command_ASDF(int client, int args)
{
	PrintToServer("res = %d", WRSJ_QueryMapWithFunc("bhop_badges", false, QueryFinished, 0x69));
	return Plugin_Handled;
}
*/
native bool WRSJ_QueryMapWithFunc(const char[] map, bool cached_results_okay, WRSJ_QueryFinishedFunc func, any callerdata);

/**
 * Called when WRSJ has some results for the map.
 *
 * @param map                       Map name...
 * @param success                   If results could not be retrieved, this is `null`. On success it will be an ArrayList of WRSJ_RecordInfo's.
 * @noreturn
 */
forward void WRSJ_OnQueryFinished(const char map[PLATFORM_MAX_PATH], ArrayList records);


public SharedPlugin __pl_wrsj =
{
	name = "wrsj",
	file = "wrsj.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_wrsj_SetNTVOptional()
{
	MarkNativeAsOptional("WRSJ_QueryMap");
	MarkNativeAsOptional("WRSJ_QueryMapWithFunc");
}
#endif
