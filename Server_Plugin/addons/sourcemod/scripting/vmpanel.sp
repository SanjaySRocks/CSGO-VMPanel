#pragma semicolon 1
#include <sourcemod>
#include <multicolors>

//Global variables
char gS_VMP_dbconfig[] = "vmpanel";
ConVar gC_VMP_servertable;
ConVar gC_VMP_alertenable;
ConVar gC_VMP_alerttimer;
ConVar gC_VMP_alertdays;
ConVar gC_VMP_panelurl;
ConVar gC_VMP_defaultvipflag;
ConVar gC_VMP_alertdisplaytype;
Database gH_VMP_dbhandler = null;

//Plugin info
public Plugin myinfo = {
  name = "SM VMPanel ",
  author = "Summer Soldier",
  description = "CSGO Plugin for VMPanel Project",
  version = "2.1.1",
  url = "https://github.com/Summer-16/CSGO-VMPanel"
};

public void OnPluginStart() {
  //Plugin Cvars
  gC_VMP_servertable = CreateConVar("sm_vmpServerTable", "sv_table", "PLEASE READ !, Enter Name for the table of current server , a table in vmpanel db will be created with this name automatically, make sure to give a unique name(name should not match with any other server connected in vmpanel), this name will be used in table name when you gonna add this server in panel");
  gC_VMP_panelurl = CreateConVar("sm_vmpPanelURL", "vmpanel.example", "Enter the URL of Your panel");
  gC_VMP_defaultvipflag = CreateConVar("sm_vmpDefaultVIPFlag", "0:a", "default vip flag and immunity to be used in add vip command");
  gC_VMP_alertenable = CreateConVar("sm_vmpAlertEnable", "1", "Should plugin display subsciption expiring alert to clients");
  gC_VMP_alerttimer = CreateConVar("sm_vmpAlertTimer", "20.0", "When the Subscribtion Expiring alert should be displayed after the player join in the server (in seconds)");
  gC_VMP_alertdays = CreateConVar("sm_vmpAlertdays", "2", "At how many days left user should be notified");
  gC_VMP_alertdisplaytype = CreateConVar("sm_vmpAlertDisplayType", "1", "1-> Menu, 2-> Chat Text (in what format should plugin show vip expiry alert)");

  //Plugin Commands
  RegConsoleCmd("sm_vipRefresh", handler_RefreshVipAndAdmins);
  RegConsoleCmd("sm_vipStatus", handler_getUserVIPStatus);
  RegAdminCmd("sm_addVip", handler_addVIP, ADMFLAG_ROOT, "Adds a VIP Usage: sm_addVip \"<SteamID>\" <Duration in days> <Name>");

  // Execute the config file, create if not present
  AutoExecConfig(true, "VMPanel");
  
  CSetPrefix("{lightred}[VIP] ");
}

//-----------------------------------------------------------------------------------------------------------------------------------------------------------------
// Functions
// Function called once in all maps after all configs get executed
public void OnConfigsExecuted() {
  //check for db connection
  if (gH_VMP_dbhandler == null) {
    PrintToServer("***[VMP] Database connection is null in , Making a new Connection Now");
    SQL_DBConnect();
  } else {
    PrintToServer("***[VMP] Database Connection is availabe refreshing Admins and VIPs Now");
    refreshVipAndAdmins();
  }
}

// Function called for all clients once on entring in server
public OnClientPostAdminCheck(client) {
  CreateTimer(GetConVarInt(gC_VMP_alerttimer), handler_onclientconnecttimer, client);
}

// Function to make sql connection
void SQL_DBConnect() {
  PrintToServer("***[VMP] Making a Database Connection");

  if (gH_VMP_dbhandler != null)
    delete gH_VMP_dbhandler;

  if (SQL_CheckConfig(gS_VMP_dbconfig)) {
    Database.Connect(SQLConnect_Callback, gS_VMP_dbconfig);
  } else {
    PrintToServer("***[VMP] Error Whike Making a Database Connection, Plugin config missing from databases.cfg file ");
    LogError("[VMP] Startup failed. Error: %s", "\"vmpanel\" is not a specified entry in databases.cfg.");
  }
}

// function to refresh vip/admins
void refreshVipAndAdmins() {
  char ls_VMP_sqltable[512];
  gC_VMP_servertable.GetString(ls_VMP_sqltable, sizeof(ls_VMP_sqltable));
  char vipListQuery[4096];
  Format(vipListQuery, sizeof(vipListQuery), "SELECT authId, flag, name FROM %s", ls_VMP_sqltable);
  gH_VMP_dbhandler.Query(refreshVipAndAdmins_Callback, vipListQuery, DBPrio_High);
}
//-----------------------------------------------------------------------------------------------------------------------------------------------------------------

//-----------------------------------------------------------------------------------------------------------------------------------------------------------------
// Handlers
// Nothing callback for sql queries which do not return any results
public void Nothing_Callback(Database db, DBResultSet result, char[] error, any data) {

  if (result == null)
    LogError("[VMP] Error: %s", error);
}

// Nothing callback for sql queries which do not return any results
public void Nothing_Callback_addVip(Database db, DBResultSet result, char[] error, any client) {

  if (result == null) {
    LogError("[VMP] Error: %s", error);
    CPrintToChat(client, "{green}Operation Failed , Error: %s", error);
  } else {
    CPrintToChat(client, "{green}VIP Successfully added , Refreshing Cahche in Admin File and In Server");
    refreshVipAndAdmins();

    char clientName[50], ls_VMP_addAuditQuery[4096];
    GetClientName(client, clientName, sizeof(clientName));
    Format(ls_VMP_addAuditQuery, sizeof(ls_VMP_addAuditQuery), "INSERT INTO tbl_audit_logs (activity, additional_info, created_by, created_at) values ('New VIP added', 'Added Through Plugin', '%s', NOW());", clientName);

    gH_VMP_dbhandler.Query(Nothing_Callback, ls_VMP_addAuditQuery, DBPrio_High);

  }
}

// handler to be called when vip/admin refresh command is called
public Action handler_RefreshVipAndAdmins(int client, int args) {

  PrintToServer("***[VMP] Executing manual refresh triggered by command");
  // PrintToServer("***[VMP] here is client for checking====> %d", client);

  if ((client == 0) || (CheckCommandAccess(client, "", ADMFLAG_GENERIC))) {
    if (client > 0) {
      CPrintToChat(client, "{green}Updating the VIP/Admin in Server");
    }
    PrintToServer("***[VMP] Requesting user is an Admin/Console, Executing the command");
    refreshVipAndAdmins();
  } else {
    CPrintToChat(client, "{green}You need admin rights to access this command");
  }
}

// handler for vmpstatus command 
public Action handler_getUserVIPStatus(int client, int type) {

  PrintToServer("***[VMP] User requested for VIP status");

  if (!IsFakeClient(client)) {
    if (CheckCommandAccess(client, "", ADMFLAG_RESERVATION)) {

      if (type != 2) {
        CPrintToChat(client, "{green}Hold On Getting your Data now.");
      }

      char ls_VMP_sqltable[512];
      gC_VMP_servertable.GetString(ls_VMP_sqltable, sizeof(ls_VMP_sqltable));
      char vipStatusQuery[4096];
      char clientSTEAMID[100];

      GetClientAuthId(client, AuthId_Engine, clientSTEAMID, sizeof(clientSTEAMID), true);

      Format(vipStatusQuery, sizeof(vipStatusQuery), "SELECT name, expireStamp FROM %s where authId = '\"%s\"'", ls_VMP_sqltable, clientSTEAMID);
      // PrintToServer("***[VMP] query is here %s : ",vipStatusQuery);

      if (type == 2) {
        gH_VMP_dbhandler.Query(getUserVIPStatusAlert_callback, vipStatusQuery, client);
      } else {
        gH_VMP_dbhandler.Query(getUserVIPStatus_callback, vipStatusQuery, client);
      }
    } else {
      char ls_VMP_panelurl[512];
      gC_VMP_panelurl.GetString(ls_VMP_panelurl, sizeof(ls_VMP_panelurl));
      CPrintToChat(client, "{green}You are not a VIP, Visit {darkred}%s {green}to purcahse now", ls_VMP_panelurl);
    }
  }
}

// handler for add vip command
public Action handler_addVIP(int client, int args) {

  if (args < 3) {
    if (client != 0)
      CPrintToChat(client, "{green}Invalid Params Usage: sm_addVip \"<SteamID>\" <Duration in days> <Name>");
    else
      PrintToServer("***[VMP] Invalid Params Usage:  sm_addVip \"<SteamID>\" <Duration in days> <Name>");
    return Plugin_Handled;
  }

  char tempArgument[50], steamId[50], userName[50];
  int subDays = 0;

  GetCmdArg(1, tempArgument, sizeof(tempArgument));
  if (StrContains(tempArgument, "STEAM_", true) == -1) {
    if (client != 0)
      CPrintToChat(client, "{green}Invalid Steam Id format use STEAM_X:X:XXXXXXX");
    else
      PrintToServer("***[VMP] Invalid Steam Id format use STEAM_X:X:XXXXXXX");
    return Plugin_Handled;
  } else {
    strcopy(steamId, sizeof(steamId), tempArgument);
  }

  GetCmdArg(2, tempArgument, sizeof(tempArgument));
  subDays = StringToInt(tempArgument);
  subDays = ((subDays * 86400) + GetTime());

  GetCmdArg(3, userName, sizeof(userName));

  // CPrintToChat(client, "{green}Here are the final args Steam: %s, Epoc: %d, Name: %s",steamId,subDays,userName);

  char ls_VMP_sqltable[512];
  gC_VMP_servertable.GetString(ls_VMP_sqltable, sizeof(ls_VMP_sqltable));
  char ls_VMP_vipFlag[50];
  gC_VMP_defaultvipflag.GetString(ls_VMP_vipFlag, sizeof(ls_VMP_vipFlag));

  char ls_VMP_addVipQuery[4096];
  Format(ls_VMP_addVipQuery, sizeof(ls_VMP_addVipQuery), "INSERT INTO %s (authid, flag, name, expireStamp, created_at ,type) values ('\"%s\"', '\"%s\"', '//%s', %d, NOW(), 0);", ls_VMP_sqltable, steamId, ls_VMP_vipFlag, userName, subDays);

  gH_VMP_dbhandler.Query(Nothing_Callback_addVip, ls_VMP_addVipQuery, client);
	
  ReplyToCommand(client, "----------------------");
  ReplyToCommand(client, "%s with steamid %s is added to vip with access flags %s for %i days", userName, steamId, ls_VMP_vipFlag, subDays);
  ReplyToCommand(client, "----------------------");
  
  return Plugin_Handled;
}

// handler for checking if server is already added in panel
public Action handler_CheckServerExistsInPanel() {
  char ls_VMP_sqltable[512];
  gC_VMP_servertable.GetString(ls_VMP_sqltable, sizeof(ls_VMP_sqltable));
  char serverCheckQuery[4096];
  Format(serverCheckQuery, sizeof(serverCheckQuery), "SELECT id FROM tbl_servers where tbl_name = '%s'", ls_VMP_sqltable);

  gH_VMP_dbhandler.Query(CheckServerExistsInPanel_callback, serverCheckQuery, DBPrio_High);
}

// timer handler for timer executed in OnClientConnect
public Action: handler_onclientconnecttimer(Handle: timer, any: client) {
  if(!IsClientInGame(client))
  	return;
	
  if ((GetConVarInt(gC_VMP_alertenable) == 1) && (CheckCommandAccess(client, "", ADMFLAG_RESERVATION)) && !IsFakeClient(client)) {
    CreateTimer(GetConVarFloat(gC_VMP_alerttimer), handler_checkUserSubForAlert, client);
  }
}

// timer handler for timer to check and show sub alert to user
public Action: handler_checkUserSubForAlert(Handle: timer, any: client) {
  
  if(!IsClientInGame(client))
  	return;
  
  handler_getUserVIPStatus(client, 2);
}

// handler for menu
public int subStatus_menu_Handler(Menu menu, MenuAction action, int param1, int param2) {
  /* Close the menu in case of any selection */
  if (action == MenuAction_Select) {
    // delete menu;
    // Do nothing
  }
  /* Close the menu in case of any selection */
  else if (action == MenuAction_Cancel) {
    PrintToServer("Client %d's menu was cancelled.  Reason: %d", param1, param2);
  }
  /* If the menu has ended, destroy it */
  else if (action == MenuAction_End) {
    delete menu;
  }
}
//-----------------------------------------------------------------------------------------------------------------------------------------------------------------

//-----------------------------------------------------------------------------------------------------------------------------------------------------------------
// Callbacks
// Callback to execute on successfull sql connection
public void SQLConnect_Callback(Database db, char[] error, any data) {

  PrintToServer("***[VMP] SQL Connection created succesfully");

  if (db == null) {
    PrintToServer("***[VMP] Can't connect to SQL server. Error: %s", error);
    LogError("[VMP] Can't connect to SQL server. Error: %s", error);
    return;
  }

  gH_VMP_dbhandler = db;
  char ls_VMP_sqltable[512];
  gC_VMP_servertable.GetString(ls_VMP_sqltable, sizeof(ls_VMP_sqltable));

  char ls_VMP_tablecreatequery[4096];
  Format(ls_VMP_tablecreatequery, sizeof(ls_VMP_tablecreatequery),
    "CREATE TABLE IF NOT EXISTS `%s` ( \
                    `authId` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL, \
                    `flag` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT '\"0:a\"', \
                    `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL, \
                    `expireStamp` int(20) unsigned NOT NULL, \
                    `created_at` datetime NOT NULL, \
                    `type` int(20) NOT NULL, \
                    PRIMARY KEY (`authId`) \
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci", ls_VMP_sqltable);

  gH_VMP_dbhandler.Query(Nothing_Callback, ls_VMP_tablecreatequery, DBPrio_High);

  handler_CheckServerExistsInPanel();
}

// callback to execute when vip/admin data fetch query is ececuted
public void refreshVipAndAdmins_Callback(Database db, DBResultSet result, char[] error, any data) {

  if (result == null) {
    PrintToServer("***[VMP] Query Fail: %s", error);
    LogError("[VMP] Query Fail: %s", error);
    return;
  }

  PrintToServer("***[VMP] Result fetch done , opening admin file for writing***");

  new String: g_sFilePath[PLATFORM_MAX_PATH];
  BuildPath(Path_SM, g_sFilePath, sizeof(g_sFilePath), "/configs/admins_simple.ini");
  new Handle: FileHandle = OpenFile(g_sFilePath, "w");
  WriteFileLine(FileHandle, "//This file is maintained by VMPanel Plugin v2.1.1, Do not add any entries in this file as they will be overwritten by plugin");

  while (result.FetchRow()) {
    char authId[100];
    char flag[100];
    char name[100];
    result.FetchString(0, authId, sizeof(authId));
    result.FetchString(1, flag, sizeof(flag));
    result.FetchString(2, name, sizeof(name));
    PrintToServer("***[VMP] fetched entries || ===> %s %s %s ", authId, flag, name);
    WriteFileLine(FileHandle, "%s  %s  %s ", authId, flag, name);
  }

  CloseHandle(FileHandle);

  PrintToServer("***[VMP] All Entries updated in admin file, Reloading Admins in server Now");
  ServerCommand("sm_reloadadmins");
  ServerCommand("sm_reloadtags"); //to update player tag for hextags plugin
}

// callback to execute when user data fetch query is ececuted for sub status
public void getUserVIPStatus_callback(Database db, DBResultSet result, char[] error, any client) {

  if (result == null) {
    PrintToServer("***[VMP] Query Fail: %s", error);
    LogError("[VMP] Query Fail: %s", error);
    CPrintToChat(client, "{green}Your VIP is active but could not find your status in Database");
    return;
  }

  while (result.FetchRow()) {
    char name[100];

    result.FetchString(0, name, sizeof(name));
    int expireEpoc = result.FetchInt(1);
    int currentEpoc = GetTime();
    int subDays = ((expireEpoc - currentEpoc) / 86400);
    // CPrintToChat(client, "subDays==>",subDays);

    char menuItem[500];
    Menu menu = new Menu(subStatus_menu_Handler);
    menu.SetTitle("Here is your VIP Subscription details, For this Server");
    menu.AddItem("", "Subscription Status : Active");
    Format(menuItem, sizeof(menuItem), "Subscriber Name : %s", name);
    menu.AddItem("", menuItem);
    Format(menuItem, sizeof(menuItem), "Subscription Days Left : %d", subDays);
    menu.AddItem("", menuItem);
    menu.ExitButton = true;
    menu.Display(client, 10);
  }
}

// callback to execute when user data fetch query is ececuted for sub alert
public void getUserVIPStatusAlert_callback(Database db, DBResultSet result, char[] error, any client) {

  if (result == null) {
    PrintToServer("***[VMP] Query Fail: %s", error);
    LogError("[VMP] Query Fail: %s", error);
    CPrintToChat(client, "{green}Your VIP is active but could not find your status in Database");
    return;
  }

  while (result.FetchRow()) {
    char name[100];

    result.FetchString(0, name, sizeof(name));
    int expireEpoc = result.FetchInt(1);
    int currentEpoc = GetTime();
    int subDays = ((expireEpoc - currentEpoc) / 86400);
	
	if(subDays < 0){
		CPrintToChat(client, "{green}You have unlimited days in your subscription");
		return;
	}
	
    if (subDays <= GetConVarInt(gC_VMP_alertdays)) {
      char ls_VMP_panelurl[512];
      gC_VMP_panelurl.GetString(ls_VMP_panelurl, sizeof(ls_VMP_panelurl));

      if ((GetConVarInt(gC_VMP_alertdisplaytype) == 1)) {
        char menuItem[500];
        Menu menu = new Menu(subStatus_menu_Handler);
        menu.SetTitle("Your VIP Subscription is about to expire, \nPlease renew to continue using VIP benefits");
        menu.AddItem("", "Subscription Status : About to Expire");
        Format(menuItem, sizeof(menuItem), "Subscriber Name : %s", name);
        menu.AddItem("", menuItem);
        Format(menuItem, sizeof(menuItem), "Subscription Days Left : %d", subDays);
        menu.AddItem("", menuItem);
        Format(menuItem, sizeof(menuItem), "Visit %s to Renew now", ls_VMP_panelurl);
        menu.AddItem("", menuItem);
        menu.ExitButton = true;
        menu.Display(client, 10);
      } else if ((GetConVarInt(gC_VMP_alertdisplaytype) == 2)) {
        CPrintToChat(client, "{green}Your VIP Subscription is about to expire");
        CPrintToChat(client, "{green}Please renew to continue using VIP benefits");
        CPrintToChat(client, "{green}Subscriber Name : {lightblue}%s ", name);
        CPrintToChat(client, "{green}Subscription Days Left : {darkred}%d ", subDays);
        CPrintToChat(client, "{green}Visit {darkred}%s {green}to Renew now", ls_VMP_panelurl);
      }
    }
  }
}

// callback to execute when check server exist query return data from db
public void CheckServerExistsInPanel_callback(Database db, DBResultSet result, char[] error, any data) {

  if (result == null) {
    PrintToServer("***[VMP] Query Fail: %s", error);
    LogError("[VMP] Query Fail: %s", error);
    return;
  }

  int checkCount = 0, resultId = 0;

  while (result.FetchRow()) {
    resultId = result.FetchInt(0);
    checkCount++;
  }

  if (checkCount == 0 && resultId == 0) {
    new String: port[10];
    GetConVarString(FindConVar("hostport"), port, sizeof(port));

    new String: serverIP[32];
    new serverIPPieces[4];
    new serverIPRaw = GetConVarInt(FindConVar("hostip"));
    serverIPPieces[0] = (serverIPRaw >> 24) & 0x000000FF;
    serverIPPieces[1] = (serverIPRaw >> 16) & 0x000000FF;
    serverIPPieces[2] = (serverIPRaw >> 8) & 0x000000FF;
    serverIPPieces[3] = serverIPRaw & 0x000000FF;
    Format(serverIP, sizeof(serverIP), "%d.%d.%d.%d", serverIPPieces[0], serverIPPieces[1], serverIPPieces[2], serverIPPieces[3]);

    char ls_VMP_sqltable[512], ls_VMP_vipFlag[50];
    gC_VMP_servertable.GetString(ls_VMP_sqltable, sizeof(ls_VMP_sqltable));
    gC_VMP_defaultvipflag.GetString(ls_VMP_vipFlag, sizeof(ls_VMP_vipFlag));
    char ls_VMP_AddServerinPanelQuery[4096];
    Format(ls_VMP_AddServerinPanelQuery, sizeof(ls_VMP_AddServerinPanelQuery), "INSERT INTO tbl_servers (tbl_name, server_name, server_ip, server_port, vip_flag) VALUES ('%s', '%s', '%s', '%s', '\"%s\"');", ls_VMP_sqltable, ls_VMP_sqltable, serverIP, port, ls_VMP_vipFlag);

    gH_VMP_dbhandler.Query(Nothing_Callback, ls_VMP_AddServerinPanelQuery, DBPrio_High);
  }
}
