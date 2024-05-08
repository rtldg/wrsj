/*
 * WRSJ by rtldg
 * Contributions by Nairda (menu stuff), @sneak-it, and @akanora
 * https://github.com/rtldg/wrsj/graphs/contributors
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

#include <sourcemod>
#include <convar_class>
#include <adt_trie> // StringMap

#include <wrsj>

#define USE_RIPEXT 1
#if USE_RIPEXT
#include <ripext> // https://github.com/ErikMinekus/sm-ripext
#else
#include <json> // https://github.com/clugg/sm-json
#include <SteamWorks> // HTTP stuff
#endif

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name = "Sourcejump World Record",
	author = "rtldg & Nairda",
	description = "Grabs WRs from Sourcejump's API",
	version = "1.17",
	url = "https://github.com/rtldg/wrsj"
}

native int Shavit_GetClientTrack(int client);
native int Shavit_GetBhopStyle(int client);
native int Shavit_GetReplayBotStyle(int entity);
native int Shavit_GetReplayBotTrack(int entity);
native bool Shavit_IsReplayEntity(int ent);

Convar gCV_SourceJumpAPIKey;
Convar gCV_SourceJumpAPIUrl;
Convar gCV_SourceJumpDelay;
Convar gCV_SourceJumpCacheSize;
Convar gCV_SourceJumpCacheTime;
Convar gCV_SourceJumpWRCount;
Convar gCV_ShowInTopleft;
Convar gCV_AfterTopleft;
Convar gCV_TrimTopleft;
Convar gCV_ShowForEveryStyle;
Convar gCV_ShowTierInTopleft;

StringMap gS_Maps;
StringMap gS_MapsCachedTime;

int gI_CurrentPagePosition[MAXPLAYERS + 1];
char gS_ClientMap[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
char gS_CurrentMap[PLATFORM_MAX_PATH];

Handle gH_Forwards_OnQueryFinished = null;


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Shavit_GetClientTrack");
	MarkNativeAsOptional("Shavit_GetBhopStyle");
	MarkNativeAsOptional("Shavit_GetReplayBotStyle");
	MarkNativeAsOptional("Shavit_GetReplayBotTrack");
	MarkNativeAsOptional("Shavit_IsReplayEntity");

	gH_Forwards_OnQueryFinished = CreateGlobalForward("WRSJ_OnQueryFinished", ET_Ignore, Param_String, Param_Cell);

	CreateNative("WRSJ_QueryMap", Native_QueryMap);
	CreateNative("WRSJ_QueryMapWithFunc", Native_QueryMapWithFunc);

	RegPluginLibrary("wrsj");

	return APLRes_Success;
}

public void OnPluginStart()
{
	gCV_SourceJumpAPIKey = new Convar("sj_api_key", "", "Replace with your unique api key. (or use 'SJPublicAPIKey')", FCVAR_PROTECTED);
	gCV_SourceJumpAPIUrl = new Convar("sj_api_url", "https://sourcejump.net/api/records/", "Can be changed for testing.", FCVAR_PROTECTED);
	gCV_SourceJumpDelay = new Convar("sj_api_delay", "1.0", "Minimum delay between requests to Sourcejump API.", 0, true, 0.5);
	gCV_SourceJumpCacheSize = new Convar("sj_api_cache_size", "12", "Number of maps to cache from Sourcejump API.");
	gCV_SourceJumpCacheTime = new Convar("sj_api_cache_time", "666.0", "How many seconds to cache a map from Sourcejump API.", 0, true, 5.0);
	gCV_SourceJumpWRCount = new Convar("sj_api_wr_count", "50", "How many top times should be shown in the !wrsj menu.", 0, true, 0.0);
	gCV_ShowInTopleft = new Convar("sj_show_topleft", "1", "Whether to show the SJ WR be shown in the top-left text.", 0, true, 0.0, true, 1.0);
	gCV_ShowTierInTopleft = new Convar("sj_show_tier_topleft", "0", "Show tier in top-left text.", 0, true, 0.0, true, 1.0);
	gCV_AfterTopleft = new Convar("sj_after_topleft", "0", "Should the top-left text go before or after server WR&PB...", 0, true, 0.0, true, 1.0);
	gCV_TrimTopleft = new Convar("sj_trim_topleft", "0", "Should the top-left text be trimmed (so the SJ WR would be at the top if there's no server WR for example).", 0, true, 0.0, true, 1.0);
	gCV_ShowForEveryStyle = new Convar("sj_every_style", "1", "Should the top-left text be shown for every style that's not Normal also?", 0, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_wrsj", Command_WRSJ, "View global world records from Sourcejump's API.");
	RegConsoleCmd("sm_sjwr", Command_WRSJ, "View global world records from Sourcejump's API.");

	gS_Maps = new StringMap();
	gS_MapsCachedTime = new StringMap();

	Convar.AutoExecConfig();
}

public void OnMapStart()
{
	GetCurrentMap(gS_CurrentMap, sizeof(gS_CurrentMap));
	GetMapDisplayName(gS_CurrentMap, gS_CurrentMap, sizeof(gS_CurrentMap));
}

public void OnConfigsExecuted()
{
	RetrieveWRSJ(0, gS_CurrentMap);
}

public Action Shavit_OnTopLeftHUD(int client, int target, char[] topleft, int topleftlength)
{
	if (!gCV_ShowInTopleft.BoolValue)
		return Plugin_Continue;

	ArrayList records;

	if (!gS_Maps.GetValue(gS_CurrentMap, records) || !records || !records.Length)
		return Plugin_Continue;

	int isReplay = !(1<=target<=MaxClients) || IsFakeClient(target);// || Shavit_IsReplayEntity(target);
	int style = isReplay ? Shavit_GetReplayBotStyle(target) : Shavit_GetBhopStyle(target);
	int track = isReplay ? Shavit_GetReplayBotTrack(target) : Shavit_GetClientTrack(target);
	style = (style == -1) ? 0 : style; // central replay bot probably
	track = (track == -1) ? 0 : track; // central replay bot probably

	if ((!gCV_ShowForEveryStyle.BoolValue && style != 0) || track != 0)
		return Plugin_Continue;

	WRSJ_RecordInfo info;
	records.GetArray(0, info);

	char sjtext[80];
	FormatEx(sjtext, sizeof(sjtext), "SJ: %s (%s)", info.time, info.name);
	if (gCV_ShowTierInTopleft.BoolValue)
		Format(sjtext, sizeof(sjtext), "%s (T%d)", sjtext, info.tier);

	if (gCV_AfterTopleft.BoolValue)
		Format(
			topleft,
			topleftlength,
			"%s%s\n%s",
			(StrContains(topleft, "\n", true) != -1) ? "" : "\n",
			topleft,
			sjtext
		);
	else
		Format(topleft, topleftlength, "%s\n%s", sjtext, topleft);

	if (gCV_TrimTopleft.BoolValue)
		TrimString(topleft);

	return Plugin_Changed;
}

Action Timer_Refresh(Handle timer, any data)
{
	RetrieveWRSJ(0, gS_CurrentMap);
	return Plugin_Stop;
}

public void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track)
{
	if (style != 0 || track != 0)
		return;

	ArrayList records;

	if (!gS_Maps.GetValue(gS_CurrentMap, records) || !records || !records.Length)
		return;

	WRSJ_RecordInfo info;
	records.GetArray(0, info);

	if (time < StringToFloat(info.time))
		CreateTimer(5.0, Timer_Refresh, 0, TIMER_FLAG_NO_MAPCHANGE);
}

void BuildWRSJMenu(int client, char[] mapname, int first_item=0)
{
	ArrayList records;
	gS_Maps.GetValue(mapname, records);

	int maxrecords = gCV_SourceJumpWRCount.IntValue;
	maxrecords = (maxrecords < records.Length) ? maxrecords : records.Length;

	Menu menu = new Menu(Handler_WRSJMenu, MENU_ACTIONS_ALL);
	menu.SetTitle("SourceJump WR\n%s - Showing %i best", mapname, maxrecords);

	for (int i = 0; i < maxrecords; i++)
	{
		WRSJ_RecordInfo record;
		records.GetArray(i, record, sizeof(record));

		char line[128];
		FormatEx(line, sizeof(line), "#%d - %s - %s (%d Jumps)", i+1, record.name, record.time, record.jumps);

		char info[PLATFORM_MAX_PATH*2];
		FormatEx(info, sizeof(info), "%d;%s", record.id, mapname);
		menu.AddItem(info, line);
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];

		FormatEx(sMenuItem, 64, "No records");
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, first_item, MENU_TIME_FOREVER);

	gI_CurrentPagePosition[client] = 0;
}

int Handler_WRSJMenu(Menu menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		int id;
		char info[PLATFORM_MAX_PATH*2];
		menu.GetItem(choice, info, sizeof(info));

		if (StringToInt(info) == -1)
		{
			return 0;
		}

		char exploded[2][PLATFORM_MAX_PATH];
		ExplodeString(info, ";", exploded, 2, PLATFORM_MAX_PATH, true);

		id = StringToInt(exploded[0]);
		gS_ClientMap[client] = exploded[1];

		WRSJ_RecordInfo record;
		ArrayList records;
		gS_Maps.GetValue(gS_ClientMap[client], records);

		for (int i = 0; i < records.Length; i++)
		{
			records.GetArray(i, record, sizeof(record));
			if (record.id == id)
				break;
		}

		if (record.id != id)
		{
			return 0;
		}

		Menu submenu = new Menu(SubMenu_Handler);

		char display[234];

#if 1
		FormatEx(display, sizeof(display),
			"%s %s\n \n\
			Time: %s (%s)\n\
			Jumps: %d\n\
			Strafes: %d (%.2f%%)\n\
			Server: %s\n\
			Date: %s\n\
			%s%s%s\n ",
			record.name, record.steamid,
			record.time, record.wrDif,
			record.jumps,
			record.strafes, record.sync,
			record.hostname,
			record.date,
			record.country[0] ? "Country: " : "", record.country, record.country[0] ? "\n" : ""
		);
		submenu.SetTitle(display);

		FormatEx(display, sizeof(display), "%sA", record.steamid);
		submenu.AddItem(display, "Open Steam profile", ITEMDRAW_DEFAULT);
		FormatEx(display, sizeof(display), "%sB", record.steamid);
		submenu.AddItem(display, "Open Sourcejump profile", ITEMDRAW_DEFAULT);
#else
		FormatEx(display, sizeof(display), "%s %s", record.name, record.steamid);
		submenu.SetTitle(display);

		FormatEx(display, sizeof(display), "Time: %s (%s)", record.time, record.wrDif);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);
		FormatEx(display, sizeof(display), "Jumps: %d", record.jumps);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);
		FormatEx(display, sizeof(display), "Strafes: %d (%.2f%%)", record.strafes, record.sync);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);
		FormatEx(display, sizeof(display), "Server: %s", record.hostname);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);
		FormatEx(display, sizeof(display), "Date: %s", record.date);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);

		if (record.country[0])
		{
			FormatEx(display, sizeof(display), "Country: %s", record.country);
			submenu.AddItem("-1", display, ITEMDRAW_DISABLED);
		}
#endif

		submenu.ExitBackButton = true;
		submenu.ExitButton = true;
		submenu.Display(client, MENU_TIME_FOREVER);

		gI_CurrentPagePosition[client] = GetMenuSelectionPosition();
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

int SubMenu_Handler(Menu menu, MenuAction action, int client, int choice)
{
	static bool DONT_CLOSE_MENU = false;

	if (action == MenuAction_Select)
	{
		char info[69];
		menu.GetItem(choice, info, sizeof(info));

		if (!info[0] || info[0] != '[')
		{
			return 0;
		}

		int len = strlen(info);
		int type = info[len-1];
		info[len-1] = 0;

		if (type == 'A')
		{
			char url[192+1];
			FormatEx(url, sizeof(url), "https://steamcommunity.com/profiles/%s", info);
			ShowMOTDPanel(client, "you just lost The Game", url, MOTDPANEL_TYPE_URL);
		}
		else if (type == 'B')
		{
			char url[192+1];
			FormatEx(url, sizeof(url), "https://www.sourcejump.net/players/%s", info);
			ShowMOTDPanel(client, "you just lost The Game", url, MOTDPANEL_TYPE_URL);
		}

		DONT_CLOSE_MENU = true;
		menu.Display(client, MENU_TIME_FOREVER);

#if 0
		if (StringToInt(info) == -1)
		{
			return 0;
		}
#endif
	}
	else if (action == MenuAction_Cancel && choice == MenuCancel_ExitBack)
	{
		BuildWRSJMenu(client, gS_ClientMap[client], gI_CurrentPagePosition[client]);
	}
	else if (action == MenuAction_End)
	{
		if (!DONT_CLOSE_MENU)
			delete menu;
		DONT_CLOSE_MENU = false;
	}

	return 0;
}

stock void UppercaseString(char[] str)
{
	int i, x;
	while ((x = str[i]) != 0)
	{
		if ('a' <= x <= 'z')
			str[i] -= ('a' - 'A');
		++i;
	}
}

#if USE_RIPEXT
ArrayList CacheMap(char mapname[PLATFORM_MAX_PATH], JSONArray json)
#else
ArrayList CacheMap(char mapname[PLATFORM_MAX_PATH], JSON_Array json)
#endif
{
	ArrayList records;

	if (gS_Maps.GetValue(mapname, records))
		delete records;

	records = new ArrayList(sizeof(WRSJ_RecordInfo));

	gS_MapsCachedTime.SetValue(mapname, GetEngineTime(), true);
	gS_Maps.SetValue(mapname, records, true);

	for (int i = 0; i < json.Length; i++)
	{
#if USE_RIPEXT
		JSONObject record = view_as<JSONObject>(json.Get(i));
#else
		JSON_Object record = json.GetObject(i);
#endif

		WRSJ_RecordInfo info;
		info.id = record.GetInt("id");
		record.GetString("name", info.name, sizeof(info.name));
		record.GetString("hostname", info.hostname, sizeof(info.hostname));
		record.GetString("time", info.time, sizeof(info.time));
		record.GetString("steamid", info.steamid, sizeof(info.steamid));
		info.accountid = SteamIDToAccountID_no_64(info.steamid);
		record.GetString("date", info.date, sizeof(info.date));
		record.GetString("wrDif", info.wrDif, sizeof(info.wrDif));
		info.sync = record.GetFloat("sync");
		info.strafes = record.GetInt("strafes");
		info.jumps = record.GetInt("jumps");
		info.tier = record.GetInt("tier");
		record.GetString("country", info.country, sizeof(info.country));
		UppercaseString(info.country);

		records.PushArray(info, sizeof(info));

#if USE_RIPEXT
		delete record;
#else
		// we fully delete the json tree later
#endif
	}

	CallOnQueryFinishedCallback(mapname, records);
	return records;
}

#if USE_RIPEXT
void RequestCallback(HTTPResponse response, DataPack pack, const char[] error)
#else
void ResponseBodyCallback(const char[] data, DataPack pack)
#endif
{
	pack.Reset();

	int client = GetClientFromSerial(pack.ReadCell());
	char mapname[PLATFORM_MAX_PATH];
	pack.ReadString(mapname, sizeof(mapname));

	DataPack AAAAA = pack.ReadCell();

	CloseHandle(pack);

#if USE_RIPEXT
	//PrintToChat(client, "status = %d, error = '%s'", response.Status, error);
	if (response.Status != HTTPStatus_OK)
	{
		CallOnQueryFinishedCallback(mapname, null);
		if (AAAAA)
			CallOnQueryFinishedWithFunctionCallback(mapname, null, AAAAA);

		if (client != 0)
			PrintToChat(client, "WRSJ: Sourcejump API request failed");
		LogError("WRSJ: Sourcejump API request failed");
		return;
	}

	JSONArray records = view_as<JSONArray>(response.Data);
#else
	JSON_Array records = view_as<JSON_Array>(json_decode(data));
	if (records == null)
	{
		CallOnQueryFinishedCallback(mapname, null);
		if (AAAAA)
			CallOnQueryFinishedWithFunctionCallback(mapname, null, AAAAA);

		if (client != 0)
			ReplyToCommand(client, "WRSJ: bbb");
		LogError("WRSJ: bbb");
		return;
	}
#endif

	ArrayList records2 = CacheMap(mapname, records);

#if USE_RIPEXT
	// the records handle is closed by ripext post-callback
#else
	json_cleanup(records);
#endif

	if (AAAAA)
		CallOnQueryFinishedWithFunctionCallback(mapname, records2, AAAAA);

	if (client != 0)
		BuildWRSJMenu(client, mapname);
}

#if !USE_RIPEXT
public void RequestCompletedCallback(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack pack)
{
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());

	//ReplyToCommand(client, "bFailure = %d, bRequestSuccessful = %d, eStatusCode = %d", bFailure, bRequestSuccessful, eStatusCode);

	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		char map[PLATFORM_MAX_PATH];
		pack.ReadString(map, sizeof(map));
		CallOnQueryFinishedCallback(map, null);
		DataPack AAAAA = pack.ReadCell();
		if (AAAAA)
			CallOnQueryFinishedWithFunctionCallback(map, null, AAAAA);
		delete pack;

		if (client != 0)
			ReplyToCommand(client, "WRSJ: Sourcejump API request failed");
		LogError("WRSJ: Sourcejump API request failed");
		return;
	}

	SteamWorks_GetHTTPResponseBodyCallback(request, ResponseBodyCallback, pack);
}
#endif

bool RetrieveWRSJ(int client, char[] mapname, DataPack MOREPACKS=null)
{
	int serial = client ? GetClientSerial(client) : 0;
	char apikey[40];
	char apiurl[230];

	gCV_SourceJumpAPIKey.GetString(apikey, sizeof(apikey));
	gCV_SourceJumpAPIUrl.GetString(apiurl, sizeof(apiurl));

	if (apikey[0] == 0 || apiurl[0] == 0)
	{
		ReplyToCommand(client, "WRSJ: Sourcejump API key or URL is not set.");
		LogError("WRSJ: Sourcejump API key or URL is not set.");
		return false;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(serial);
	pack.WriteString(mapname);
	pack.WriteCell(MOREPACKS);

	StrCat(apiurl, sizeof(apiurl), mapname);
	//ReplyToCommand(client, "url = %s", apiurl);

#if USE_RIPEXT
	HTTPRequest http = new HTTPRequest(apiurl);
	http.SetHeader("api-key", "%s", apikey);
	http.Get(RequestCallback, pack);
#else
	Handle request;
	if (!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, apiurl))
	  || !SteamWorks_SetHTTPRequestHeaderValue(request, "api-key", apikey)
	  || !SteamWorks_SetHTTPRequestHeaderValue(request, "accept", "application/json")
	  || !SteamWorks_SetHTTPRequestContextValue(request, pack)
	  || !SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 4000)
	//|| !SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(request, true)
	  || !SteamWorks_SetHTTPCallbacks(request, RequestCompletedCallback)
	  || !SteamWorks_SendHTTPRequest(request)
	)
	{
		CloseHandle(pack);
		CloseHandle(request);
		ReplyToCommand(client, "WRSJ: failed to setup & send HTTP request");
		LogError("WRSJ: failed to setup & send HTTP request");
		return false;
	}
#endif

	return true;
}

Action Command_WRSJ(int client, int args)
{
	if (client == 0 || IsFakeClient(client))// || !IsClientAuthorized(client))
		return Plugin_Handled;

	char mapname[PLATFORM_MAX_PATH];

	if (args < 1)
		mapname = gS_CurrentMap;
	else
		GetCmdArg(1, mapname, sizeof(mapname));

	float cached_time;
	if (gS_MapsCachedTime.GetValue(mapname, cached_time))
	{
		if (cached_time > (GetEngineTime() - gCV_SourceJumpCacheTime.FloatValue))
		{
			BuildWRSJMenu(client, mapname);
			return Plugin_Handled;
		}
	}

	RetrieveWRSJ(client, mapname);
	return Plugin_Handled;
}


stock void LowercaseStringxx(char[] str)
{
	for (int i = 0; str[i] != 0; i++)
	{
		str[i] = CharToLower(str[i]);
	}
}

public any Native_QueryMap(Handle plugin, int numParams)
{
	char map[PLATFORM_MAX_PATH];
	GetNativeString(1, map, sizeof(map));
	LowercaseStringxx(map);

	bool cache_okay = GetNativeCell(2);

	if (cache_okay)
	{
		ArrayList records;

		if (gS_Maps.GetValue(map, records) && records && records.Length)
		{
			CallOnQueryFinishedCallback(map, records);
			return true;
		}
	}

	return RetrieveWRSJ(0, map);
}

public any Native_QueryMapWithFunc(Handle plugin, int numParams)
{
	char map[PLATFORM_MAX_PATH];
	GetNativeString(1, map, sizeof(map));
	LowercaseStringxx(map);

	bool cache_okay = GetNativeCell(2);

	DataPack data = new DataPack();
	data.WriteFunction(GetNativeFunction(3));
	data.WriteCell(plugin);
	data.WriteCell(GetNativeCell(4));

	if (cache_okay)
	{
		ArrayList records;

		if (gS_Maps.GetValue(map, records) && records && records.Length)
		{
			CallOnQueryFinishedWithFunctionCallback(map, records, data);
			return true;
		}
	}

	bool res = RetrieveWRSJ(0, map, data);

	if (!res)
		delete data;

	return res;
}

void CallOnQueryFinishedWithFunctionCallback(const char map[PLATFORM_MAX_PATH], ArrayList records, DataPack callerinfo)
{
	callerinfo.Reset();
	Function func = callerinfo.ReadFunction();
	Handle plugin = callerinfo.ReadCell();
	int callerdata = callerinfo.ReadCell();
	delete callerinfo;

	Call_StartFunction(plugin, func);
	Call_PushString(map);
	Call_PushCell(records);
	Call_PushCell(callerdata);
	Call_Finish();
}

void CallOnQueryFinishedCallback(const char map[PLATFORM_MAX_PATH], ArrayList records)
{
	Call_StartForward(gH_Forwards_OnQueryFinished);
	Call_PushString(map);
	Call_PushCell(records);
	Call_Finish();
}

stock int SteamIDToAccountID_no_64(const char[] sInput)
{
	char sSteamID[32];
	strcopy(sSteamID, sizeof(sSteamID), sInput);
	ReplaceString(sSteamID, 32, "\"", "");
	TrimString(sSteamID);

	if (StrContains(sSteamID, "STEAM_") != -1)
	{
		ReplaceString(sSteamID, 32, "STEAM_", "");

		char parts[3][11];
		ExplodeString(sSteamID, ":", parts, 3, 11);

		// Let X, Y and Z constants be defined by the SteamID: STEAM_X:Y:Z.
		// Using the formula W=Z*2+Y, a SteamID can be converted:
		return StringToInt(parts[2]) * 2 + StringToInt(parts[1]);
	}
	else if (StrContains(sSteamID, "U:1:") != -1)
	{
		ReplaceString(sSteamID, 32, "[", "");
		ReplaceString(sSteamID, 32, "U:1:", "");
		ReplaceString(sSteamID, 32, "]", "");

		return StringToInt(sSteamID);
	}

	return 0;
}
