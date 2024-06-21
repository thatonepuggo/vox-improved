-- shared globals
local Prefixes = {'/', '!'}
local PrefixesAsString = '(' .. table.concat( Prefixes, '|' ) .. ')'

local FlagPrefix = "--"

local Delimiter = " "

local SoundDir = "vox/"
local FullSoundDir = "sound/" .. SoundDir

local voxfiles, voxdirs = file.Find( FullSoundDir .. "/*.wav", "GAME" )

local VoxShorthands = {
	dr = "doctor",
	mr = "mister",
}

for i, v in ipairs( voxfiles ) do
	voxfiles[i] = string.Replace( v, FullSoundDir, "" )
	voxfiles[i] = string.Replace( v, ".wav", "" )
end

local NETSTRS = {
	Broadcast = "VOXBroadcast",
	List = "VOXList",
	ListButton = "VOXListButton",
}

local VoxListCmds = {
	"voxlist",
	"voxhelp",
	"voxmenu",
}

local VoxListCmdsAsString = table.concat( VoxListCmds, '/' )


-- colors

local Color_Err = Color( 255, 90, 90 )


-- shared functions

local function DoPrefix(prefixes, cmd)
	for _, prefix in ipairs( prefixes ) do
		if string.StartsWith( cmd, prefix ) then
			return string.sub( cmd, #prefix + 1 )
		end
	end
end

function table.CopyAndRemove(tbl, ind)
	local copy = table.Copy( tbl )
	table.remove( copy, ind )
	return copy
end

local function Search(val)
	if (string.Trim( val ) == "") then return voxfiles end
	local filtered = {}
	for k, v in ipairs( voxfiles ) do
		if (v:find( val )) then table.insert( filtered, v ) end
	end
	return filtered
end

VOX_ADMINONLY = CreateConVar(
	"vox_adminonly",
	1,
	FCVAR_NOTIFY,
	"Is the VOX Broadcaster admin only?"
)
VOX_DELAY = CreateConVar(
	"vox_delay",
	1,
	FCVAR_NOTIFY,
	"Delay between VOX commands"
)
VOX_BUTTONS_ARE_SV = CreateConVar(
	"vox_buttons_are_serversided",
	0,
	FCVAR_NOTIFY,
	""
)

if SERVER then
	AddCSLuaFile( 'autorun/vox.lua' )

	for _, v in pairs( NETSTRS ) do
		util.AddNetworkString( v )
	end

	VOX_NEXTBROADCAST = CurTime()

	local function VoxSvCmd(ply, cmd, args, isButton)
		-- isButton: probably bad fix but if you dont like this then don't set the value to TRUE Idiot.COM
		if (isButton or !VOX_NEXTBROADCAST or VOX_NEXTBROADCAST < CurTime()) then
			local voxline = table.concat( args, Delimiter )
			if CanBroadCast( ply ) then
				net.Start( NETSTRS.Broadcast )
					net.WriteString( voxline )
				net.Broadcast()
			end
			VOX_NEXTBROADCAST = CurTime() + VOX_DELAY:GetInt()
		end
	end

	local function VoxListCmd(ply, cmd, args)
		net.Start( NETSTRS.List )
		net.Send( ply )
	end

	local function VoxAutoComplete(cmd, args)
		args = args:Trim():lower()
		args = string.Explode( '%s+', args, true )

		local Filtered = Search( args[#args] )
		local before = table.CopyAndRemove( args, #args )

		local ret = table.Copy( Filtered )

		local cmdA = cmd

		-- why do i need to do this???
		if (#args ~= 1) then cmdA = cmdA .. " " end

		for i, v in ipairs( Filtered ) do
			ret[i] = cmdA .. table.concat( before, Delimiter ) .. Delimiter .. v
		end
		return ret
	end

	function CanBroadCast(ply)
		if (VOX_ADMINONLY:GetBool()) then
			return ply:IsAdmin()
		end
		return true
	end


	hook.Add( "PlayerInitialSpawn", NETSTRS.Broadcast, function(ply)
		timer.Simple( 5, function()
			if (!ply:IsValid()) then return end
			ply:ChatPrint( "Thanks for downloading VOX Improved! - Pug" )
			ply:ChatPrint( "Original Addon by Black Tea Za rebel1324" )
			ply:ChatPrint( PrefixesAsString .. "vox <string> will broadcast the sound! console command also works!" )
			ply:ChatPrint( PrefixesAsString .. VoxListCmdsAsString .. " will direct you to how to use this vox announcer!" )
			ply:ChatPrint( string.rep( "=", 10 ) )
			if (VOX_ADMINONLY:GetInt() == 1) then
				ply:ChatPrint( "Only admins can use VOX Broadcast in this server." )
			else
				ply:ChatPrint( "Anyone can use VOX Broadcast in this server." )
			end
		end)
	end)

	hook.Add( "PlayerSay", NETSTRS.Broadcast, function( ply, str )
		local text = DoPrefix( Prefixes, str )
		if (text) then
			local command = string.Explode( Delimiter, text )
			if (command[1] == "vox") then
				VoxSvCmd( ply, "vox", table.CopyAndRemove( command, 1 ) )
				return false
			elseif (table.HasValue( VoxListCmds, command[1] )) then
				VoxListCmd( ply )
				return false
			end
		end
	end)

	concommand.Add( "vox", VoxSvCmd, VoxAutoComplete )
	for _, v in ipairs( VoxListCmds ) do
		concommand.Add( v, VoxListCmd )
	end

	net.Receive( NETSTRS.ListButton, function(length, ply)
		local str = net.ReadString()
		if (VOX_BUTTONS_ARE_SV:GetBool() and CanBroadCast( ply )) then
			VoxSvCmd( ply, "vox", str:Split( Delimiter ) )
		end
	end)
else -- CLIENT
	VOX_PITCH = 100
	VOX_LEVEL = 70
	VOX_VOL = 1

	local flags = {
		["delay"] = function(time, input, entity)
			return { time = time + tonumber( input ) }
		end,
	}

	function voxBroadcast(string, entity, sndDat)
		local time = 0
		local ply = LocalPlayer()
		local emitEntity = entity or ply
		local tbl = string.Explode( Delimiter, string )
		for k, v in ipairs( tbl ) do
			v = string.lower( v )
			if (VoxShorthands[v]) then v = VoxShorthands[v] end
			local sndFile = SoundDir .. "/" .. v .. ".wav"

			if (string.StartsWith( v, FlagPrefix )) then
				-- run flag if exists
				v = string.sub( v, #FlagPrefix + 1 )
				local split = string.Explode( "=", v )
				local fname, fvalue = split[1], split[2]
				if (flags[fname]) then
					local result = flags[fname]( time, fvalue, emitEntity )

					if result.time then time = result.time end
				end
			else
				if (not file.Exists( "sound/" .. sndFile, "GAME" )) then
					chat.AddText( Color_Err, "No Voiceline named '" .. v .. "'!" )
					continue
				end
				if (k != 1) then
					time = time + SoundDuration( sndFile ) + .1
				end
				timer.Simple( time, function()
					if emitEntity:IsValid() then
						if emitEntity == LocalPlayer() then
							surface.PlaySound( sndFile )
						else
							local sndDat = sndDat or { pitch = VOX_PITCH, level = VOX_LEVEL, volume = VOX_VOL }
							sound.Play( sndFile, emitEntity:GetPos(), sndDat.level, sndDat.pitch, sndDat.volume )
						end
					end
				end)
			end
		end
	end

	net.Receive( NETSTRS.Broadcast, function(length)
		local str = net.ReadString()
		voxBroadcast( str )
	end)
	net.Receive( NETSTRS.List, function(length)
		local Filtered = voxfiles

		local Frame = vgui.Create( "DFrame" )
		Frame:SetTitle( "VOX Quotes List" )
		Frame:SetSize( 500, 500 )
		Frame:Center()
		Frame:MakePopup()

		local SearchBar = vgui.Create( "DTextEntry", Frame )
		SearchBar:Dock( TOP )
		SearchBar:SetPlaceholderText( "Search..." )
		SearchBar:DockMargin( 0, 0, 0, 10 )

		local ScrollPanel = vgui.Create( "DScrollPanel", Frame )
		ScrollPanel:Dock( FILL )

		local function RefreshList()
			ScrollPanel:Clear()
			for index, item in ipairs(Filtered) do
				local ListButton = ScrollPanel:Add( "DButton" )
				ListButton:SetText( item )
				ListButton:Dock( TOP )
				ListButton:DockMargin( 0, 0, 0, 5 )
				ListButton.DoClick = function(clr, btn)
					if (VOX_BUTTONS_ARE_SV:GetBool()) then
						net.Start( NETSTRS.ListButton )
							net.WriteString( item )
						net.SendToServer()
					else
						voxBroadcast( item )
					end
				end
			end
		end

		SearchBar.OnChange = function(self)
			Filtered = Search( self:GetValue() )
			RefreshList()
		end

		RefreshList()
	end)

end