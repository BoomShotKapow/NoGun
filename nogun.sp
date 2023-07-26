#include <sourcemod>
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <mycolors>

#pragma newdecls required
#pragma semicolon 1

#define SF_BUTTON_DAMAGE_ACTIVATES 512    // Button fires when damaged.
#define SF_BREAK_TRIGGER_ONLY	   0x0001 // Can only be broken by trigger
#define DRAW_DELAY                 0.5    // Delay in seconds for drawing show impacts.

public Plugin myinfo =
{
    name        = "NoGun",
    author      = "BoomShot",
    description = "Allows the player to do map mechanics without a gun.",
    version     = "1.0.1",
    url         = "https://github.com/BoomShotKapow/NoGun"
};

//command for getting a clien't name
COLOR gI_ImpactColor[MAXPLAYERS + 1];

int gI_BeamSprite;
int gI_HaloSprite;

float gF_Delay[MAXPLAYERS + 1];

Cookie gC_ShowImpactsCookie = null;
Cookie gC_ImpactColorIndex = null;

bool gB_Late;
bool gB_ShowImpacts[MAXPLAYERS + 1] = {true, ...};
bool gB_Debug;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    gB_Late = late;

    return APLRes_Success;
}

public void OnPluginStart()
{
    RegConsoleCmd("sm_nogun", Command_NoGun);

    RegAdminCmd("sm_nogun_debug", Command_Debug, ADMFLAG_ROOT);

    gC_ShowImpactsCookie = new Cookie("sm_nogunimpacts", "Toggle the displaying of the NoGun show impacts.", CookieAccess_Protected);
    gC_ImpactColorIndex = new Cookie("sm_nogunimpactcolor", "The display color of the NoGun impacts.", CookieAccess_Protected);

    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsFakeClient(client))
		{
			OnClientPutInServer(client);
		}
    }
}

public Action Command_Debug(int client, int args)
{
    gB_Debug = !gB_Debug;
    ReplyToCommand(client, "Debug Mode: %s", gB_Debug ? "Enabled" : "Disabled");

    return Plugin_Handled;
}

public void OnClientCookiesCached(int client)
{
    char cookie[4];

    gC_ShowImpactsCookie.Get(client, cookie, sizeof(cookie));
    gB_ShowImpacts[client] = (strlen(cookie) > 0) ? view_as<bool>(StringToInt(cookie)) : true;
    cookie[0] = '\0';

    gC_ImpactColorIndex.Get(client, cookie, sizeof(cookie));
    gI_ImpactColor[client] = (strlen(cookie) > 0) ? view_as<COLOR>(StringToInt(cookie)) : RED;
    cookie[0] = '\0';
}

public void OnClientPutInServer(int client)
{
    if(IsFakeClient(client))
    {
        return;
    }

    if(AreClientCookiesCached(client))
    {
        OnClientCookiesCached(client);
    }
}

public void OnClientConnected(int client)
{
    gF_Delay[client] = 0.0;
}

public void OnMapStart()
{
    gI_BeamSprite = PrecacheModel("sprites/laser.vmt", true);
    gI_HaloSprite = PrecacheModel("sprites/halo01.vmt", true);

    if(gB_Late)
    {
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientInGame(client))
            {
                OnClientConnected(client);
                OnClientPutInServer(client);
            }
        }
    }
}

public Action Command_NoGun(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    CreateNoGunMenu(client);

    return Plugin_Handled;
}

bool CreateNoGunMenu(int client, int page = 0)
{
    Menu menu = new Menu(NoGun_MenuHandler);
    menu.SetTitle("NoGun Customization Menu:\n");

    menu.AddItem("enabled", gB_ShowImpacts[client] ? "[X] Enabled" : "[ ] Enabled");
    menu.AddItem("-1", "", ITEMDRAW_SPACER);

    char display[64];
    FormatEx(display, sizeof(display), "[Impact Color]");
    menu.AddItem("impactcolor", display);

    return menu.DisplayAt(client, page, MENU_TIME_FOREVER);
}

public int NoGun_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char info[128];
            menu.GetItem(param2, info, sizeof(info));

            if(StrEqual(info, "enabled"))
            {
                gB_ShowImpacts[param1] = !gB_ShowImpacts[param1];
                gC_ShowImpactsCookie.Set(param1, gB_ShowImpacts[param1] ? "1" : "0");
            }
            else if(StrEqual(info, "impactcolor"))
            {
                CreateColorMenu(param1, gI_ImpactColor[param1], ImpactColor_MenuHandler);

                return 0;
            }

            CreateNoGunMenu(param1, menu.Selection);
        }

        case MenuAction_Cancel:
        {
            if(param2 == MenuCancel_ExitBack)
            {
                delete menu;
            }
        }
    }

    return 0;
}

public int ImpactColor_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char info[64];
            menu.GetItem(param2, info, sizeof(info));

            int color = StringToInt(info);

            char data[2];
            IntToString(color, data, sizeof(data));

            gI_ImpactColor[param1] = view_as<COLOR>(color);
            gC_ImpactColorIndex.Set(param1, data);

            CreateColorMenu(param1, view_as<COLOR>(color), ImpactColor_MenuHandler);
        }

        case MenuAction_Cancel:
        {
            if(param2 == MenuCancel_ExitBack)
            {
                CreateNoGunMenu(param1);
            }
        }
    }

    return 0;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    char curWeapon[32];
    GetClientWeapon(client, curWeapon, sizeof(curWeapon));

    if(!IsValidClient(client, true) || IsFakeClient(client) || !(buttons & IN_ATTACK) || curWeapon[0] != '\0')
    {
        return;
    }

    float eyePos[3];
    GetClientEyePosition(client, eyePos);

    float eyeAngles[3];
    GetClientEyeAngles(client, eyeAngles);

    Handle trace = TR_TraceRayFilterEx(eyePos, eyeAngles, MASK_SHOT, RayType_Infinite, TRNoClients);

    if(TR_DidHit(trace))
    {
        float endPos[3];
        TR_GetEndPosition(endPos, trace);

        TR_EnumerateEntitiesHull(eyePos, endPos, {-12.0, -12.0, -12.0}, {12.0, 12.0, 12.0}, PARTITION_SOLID_EDICTS | PARTITION_STATIC_PROPS, TREnumSolid, client);

        if(!gB_ShowImpacts[client] || (gF_Delay[client] && (GetEngineTime() - gF_Delay[client]) < DRAW_DELAY))
        {
            delete trace;

            return;
        }

        gF_Delay[client] = GetEngineTime();

        // Ignore this shitty code for drawing an ugly ass box
        float temp[3];
        temp[0] = endPos[0] - 3;
        temp[1] = endPos[1] - 3;
        temp[2] = endPos[2] + 3;

        Effect_DrawBeamBoxToClient(client, temp, endPos, gI_BeamSprite, gI_HaloSprite, 0, 60, 3.0, 3.0, 3.0, _, _, gI_ColorIndex[gI_ImpactColor[client]]);

        TE_SetupEnergySplash(endPos, NULL_VECTOR, false);
        TE_SendToClient(client, DRAW_DELAY);
    }

    delete trace;
}

bool TRNoClients(int entity, int mask)
{
    return entity > MaxClients;
}

bool TREnumSolid(int entity, any client)
{
    if((entity <= MaxClients) || !IsValidEntity(entity))
    {
        return true;
    }

    char className[32];
    GetEntityClassname(entity, className, sizeof(className));

    if(StrContains(className, "breakable") != -1 || StrContains(className, "physbox") != -1)
    {
        if(Entity_HasSpawnFlags(entity, SF_BREAK_TRIGGER_ONLY))
        {
            PrintDebug("[%s] (%d): SF_BREAK_TRIGGER_ONLY", className, entity);
            return true;
        }

        if(!AcceptEntityInput(entity, "Break", client, client))
        {
            LogError("[NoGun]: Entity [%s] - Failed to accept input: Break");
        }
    }
    else if(StrContains(className, "button") != -1)
    {
        if(!Entity_HasSpawnFlags(entity, SF_BUTTON_DAMAGE_ACTIVATES))
        {
            return true;
        }

        SDKHooks_TakeDamage(entity, 0, client, 1.0, DMG_BULLET, _, _, _, false);
    }

    return false;
}

stock bool IsValidClient(int client, bool bAlive = false)
{
    return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

stock void PrintDebug(const char[] message, any...)
{
    if(!gB_Debug)
    {
        return;
    }

    char buffer[255];
    VFormat(buffer, sizeof(buffer), message, 2);

    PrintToServer(buffer);

    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientConnected(client) && CheckCommandAccess(client, "sm_nogun_debug", ADMFLAG_ROOT))
        {
            PrintToConsole(client, buffer);
            return;
        }
    }
}

//https://github.com/bcserv/smlib/blob/aad2c8e963dbd7790096efd7920bd9f3cf76082d/scripting/include/smlib/entities.inc#L558-L561
stock bool Entity_HasSpawnFlags(int entity, int flags)
{
    return GetEntProp(entity, Prop_Data, "m_spawnflags") & flags == flags;
}

//https://github.com/bcserv/smlib/blob/aad2c8e963dbd7790096efd7920bd9f3cf76082d/scripting/include/smlib/effects.inc#L208-L227
stock void Effect_DrawBeamBoxToClient(int client, const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame = 0, int frameRate = 30, float life = 5.0, float width = 5.0, float endWidth = 5.0, int fadeLength = 2, float amplitude = 1.0, const int color[4] =  { 255, 0, 0, 255 }, int speed = 0)
{
	int clients[1]; clients[0] = client;
	Effect_DrawBeamBox(clients, 1, bottomCorner, upperCorner, modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
}

//https://github.com/bcserv/smlib/blob/aad2c8e963dbd7790096efd7920bd9f3cf76082d/scripting/include/smlib/effects.inc#L293-L349
stock void Effect_DrawBeamBox(int[] clients, int numClients, const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame = 0, int frameRate = 30, float life = 5.0, float width = 5.0, float endWidth = 5.0, int fadeLength = 2, float amplitude = 1.0, const int color[4] =  { 255, 0, 0, 255 }, int speed = 0)
{
	float corners[8][3];

	for(int i = 0; i < 4; i++)
	{
		CopyArrayToArray(bottomCorner, corners[i], 3);
		CopyArrayToArray(upperCorner, corners[i + 4], 3);
	}

	corners[1][0] = upperCorner[0];
	corners[2][0] = upperCorner[0];
	corners[2][1] = upperCorner[1];
	corners[3][1] = upperCorner[1];
	corners[4][0] = bottomCorner[0];
	corners[4][1] = bottomCorner[1];
	corners[5][1] = bottomCorner[1];
	corners[7][0] = bottomCorner[0];

	for(int i = 0; i < 4; i++)
	{
		int j = (i == 3 ? 0 : i + 1);
		TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}

	for(int i = 4; i < 8; i++)
	{
		int j = (i == 7 ? 4 : i + 1);
		TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}

	for(int i = 0; i < 4; i++)
	{
		TE_SetupBeamPoints(corners[i], corners[i + 4], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}
}

stock void CopyArrayToArray(const any[] array, any[] newArray, int size)
{
	for(int i = 0; i < size; i++)
    {
		newArray[i] = array[i];
    }
}