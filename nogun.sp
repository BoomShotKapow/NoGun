#include <clientprefs>
#include <outputinfo>
#include <smlib>
#include <sourcemod>

#pragma newdecls required
#pragma semicolon 1

#define SF_BUTTON_DAMAGE_ACTIVATES 512    // Button fires when damaged.
#define DRAW_DELAY                 0.5    // Delay in seconds for drawing show impacts.

public Plugin myinfo =
{
    name        = "NoGun",
    author      = "BoomShot",
    description = "Allows the player to do map mechanics without a gun.",
    version     = "1.0.0",
    url         = "https://github.com/BoomShotKapow/NoGun"
};

float gF_Delay[MAXPLAYERS + 1];

int gI_BeamSprite;
int gI_HaloSprite;

Cookie gC_ShowImpactsCookie = null;

bool gB_Late;
bool gB_ShowImpacts[MAXPLAYERS + 1];
bool gB_Debug;

char gS_EntityInputs[][]  = { "Damage", "Break" };
char gS_EntityOutputs[][] = { "m_OnDamaged", "m_OnBreak" };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    gB_Late = late;

    return APLRes_Success;
}

public void OnPluginStart()
{
    RegConsoleCmd("sm_nogun", Command_NoGun);

    RegAdminCmd("sm_nogun_debug", Command_Debug, ADMFLAG_ROOT);

    gC_ShowImpactsCookie = new Cookie("sm_nogunimpacts", "Toggle the displaying of the NoGun show impacts.", CookieAccess_Public);

    if(gB_Late)
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i))
            {
                OnClientPutInServer(i);
            }
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
    if(IsFakeClient(client) || !IsClientInGame(client))
    {
        return;
    }

    char cookie[4];

    if(gC_ShowImpactsCookie != null)
    {
        gC_ShowImpactsCookie.Get(client, cookie, sizeof(cookie));
    }

    gB_ShowImpacts[client] = (strlen(cookie) > 0) ? view_as<bool>(StringToInt(cookie)) : true;
}

public void OnClientPutInServer(int client)
{
    if(IsFakeClient(client))
    {
        return;
    }

    gB_ShowImpacts[client] = true;

    if(AreClientCookiesCached(client))
    {
        OnClientCookiesCached(client);
    }
}

public Action Command_NoGun(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    char data[2];
    gC_ShowImpactsCookie.Get(client, data, sizeof(data));
    gC_ShowImpactsCookie.Set(client, (data[0] == '1') ? "0" : "1");

    gB_ShowImpacts[client] = !(data[0] == '1');

    PrintToChat(client, "NoGun show impacts: %s", gB_ShowImpacts[client] ? "Enabled" : "Disabled");

    return Plugin_Handled;
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

public void OnClientConnected(int client)
{
    if(IsValidClient(client))
    {
        gF_Delay[client]       = 0.0;
        gB_ShowImpacts[client] = true;
    }
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    if(!IsValidClient(client, true) || !(buttons & IN_ATTACK) || GetPlayerWeaponSlot(client, 1) != -1)
    {
        return Plugin_Continue;
    }

    // Find all entities with the specified input/output
    TraceEntitiesFromClientView(client, angles);

    return Plugin_Continue;
}

// Credits to JoinedSenses for the original code
// https://github.com/JoinedSenses/SM-EntityDebugger/blob/233c9ff9b40cf7903cecda7746d44b2a97639bb5/scripting/entdebug.sp#L687-L772
void TraceEntitiesFromClientView(int client, float angles[3])
{
    float origin[3];
    GetClientEyePosition(client, origin);

    Handle trace = TR_TraceRayFilterEx(origin, angles, MASK_SHOT, RayType_Infinite, TRNoClients);

    if(!TR_DidHit(trace))
    {
        return;
    }

    float end[3];
    TR_GetEndPosition(end, trace);

    int entity = TR_GetEntityIndex(trace);

    delete trace;

    if(entity == -1)
    {
        PrintDebug("No entities found!");
    }

    TR_EnumerateEntities(origin, end, PARTITION_SOLID_EDICTS, RayType_EndPoint, TREnumSolidEdicts, client);

    if(gF_Delay[client] && (GetEngineTime() - gF_Delay[client]) < DRAW_DELAY)
    {
        return;
    }

    gF_Delay[client] = GetEngineTime();

    // Ignore this shitty code for drawing an ugly ass box
    float temp[3];
    temp[0] = end[0] - 3;
    temp[1] = end[1] - 3;
    temp[2] = end[2] + 3;

    if(gB_ShowImpacts[client])
    {
        Effect_DrawBeamBoxToClient(client, temp, end, gI_BeamSprite, gI_HaloSprite, 0, 60, 3.0, 3.0, 3.0);
        TE_SetupEnergySplash(end, NULL_VECTOR, false);
        TE_SendToClient(client, DRAW_DELAY);
    }
}

bool TRNoClients(int entity, int mask)
{
    return entity > MaxClients;
}

bool TREnumSolidEdicts(int entity, any client)
{
    if(entity <= MaxClients || !IsValidEntity(entity))
    {
        return true;
    }

    char className[32];
    GetEntityClassname(entity, className, sizeof(className));

    // Ignore anything that's not func_button, func_breakable_surf, etc.
    if(StrContains(className, "func_") == -1)
    {
        return true;
    }

    for(int i = 0; i < sizeof(gS_EntityInputs); i++)
    {
        if(StrContains(className, "breakable") != -1)
        {
            if(Entity_HasSpawnFlags(entity, SF_BREAK_TRIGGER_ONLY))
            {
                PrintDebug("Breakable entity [%d]: SF_BREAK_TRIGGER_ONLY", entity);
                return false;
            }
        }

        if(AcceptEntityInput(entity, gS_EntityInputs[i], client))
        {
            PrintDebug("Entity (%d) received input: %s", entity, gS_EntityInputs[i]);
        }

        if(EntHasOutputAction(entity, className, gS_EntityOutputs[i], client))
        {
            PrintDebug("Fired entity (%d) output: %s", entity, gS_EntityOutputs[i]);
        }
    }

    return true;
}

bool EntHasOutputAction(int entity, const char[] className, const char[] output, int client)
{
    char action[32];
    GetOutputActionParameter(entity, output, 0, action, sizeof(action));

    char target[32];
    GetOutputActionTargetInput(entity, output, 0, target, sizeof(target));

    if(action[0] == '\0' && target[0] == '\0')
    {
        return false;
    }

    PrintDebug("Action: [%s] || Target: [%s]", action, target);

    if(StrContains(className, "button") != -1 && Entity_HasSpawnFlags(entity, SF_BUTTON_DAMAGE_ACTIVATES))
    {
        PrintDebug("Hurting entity [%d]", entity);
        Entity_Hurt(entity, 0, client, DMG_BULLET);
    }

    return true;
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
            PrintToChat(client, buffer);
            return;
        }
    }
}
