--!strict

--[[
    MusicController.lua
    Author: Michael S (DevIrradiant)

    Description: Music controller that supports control from client and server.
]]

-- Services
local RunService = game:GetService("RunService")

-- Types
export type MusicController = {
-- Internal
    -- Record of current track Names registered by ID
    _trackNames: {string},

    -- Record of current track Sounds registered by ID
    _trackSounds: {Sound},

    -- Current ID of playing / paused track
    _currentTrack: number?,

    -- Whether or not the next track should automatically play, true by default
    _autoPlayNextTrack: boolean,

    -- Connection that will play the next track when currentTrack completes.
    _nextTrackConnection: RBXScriptConnection?,

-- External
    -- This method will bind a remote to allow Play overrides from the server
    BindRemote: (self: MusicController, remote: RemoteEvent) -> nil,

    -- This method will populate the track names and track sounds based on a supplied table of sounds.
    PopulateLibrary: (self: MusicController, library: {Sound}, conifig: Configuration) -> nil,

    -- This method returns the ID and sound of the next track in the queue
    GetTrack: (self: MusicController, track: string?) -> (number?, Sound?),

    -- This method will play the supplied track, or the next track in the queue, if either exists.
    Play: (self: MusicController, track: string?) -> nil,

    -- This method will pause the current track.
    Pause: (self: MusicController) -> nil,

    -- This method will stop the current track and cleanup any connections.
    Stop: (self: MusicController) -> nil,

    -- This method will resume the current track if one exists.
    Resume: (self: MusicController) -> nil,

    -- This method will skip the current track if one exists.
    Skip: (self: MusicController) -> nil,
}

export type Configuration = {
    autoPlayNextTrack: boolean,
}



--[=[
    @class MusicController

    A simple handler for client and server controlled Music.
]=]
local MusicController = {
    _trackNames = {},
    _trackSounds = {},
    _currentTrack = nil,
    _autoPlayNextTrack = true
} :: MusicController

--[=[
    Populates the track names and track sounds based on a supplied table of sounds.

    @within MusicController

    @param library {[number]: Sound} -- Supplied table of Sounds to populate the library with
]=]
function MusicController:PopulateLibrary(library: {Sound}, config: Configuration?)
    -- Wipe Library if already populated
    self._trackNames = {}
    self._trackSounds = {}

    -- Populate Library
    for id, sound in library do
        if typeof(sound) ~= "Instance" or not sound:IsA("Sound") then
            -- Debug
            if RunService:IsStudio() then
                warn(`supplied object is not a Sound`)
            end
            continue
        end

        self._trackNames[id] = sound.Name
        self._trackSounds[id] = sound
    end

    -- Update configuration
    if config then
        self._autoPlayNextTrack = config.autoPlayNextTrack
    end

    return
end

--[=[
    Binds a remote to allow for music updates from the server.

    @within MusicController

    @param remote RemoteEvent -- Remote bound to Play method.
]=]
function MusicController:BindRemote(remote: RemoteEvent)
    if typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
        -- Debug
        if RunService:IsStudio() then
            warn(`supplied object is not a RemoteEvent`)
        end
        return
    end

    remote.OnClientEvent:Connect(function(track: string?)
        self:Play(track)
    end)

    return
end

--[=[
    Return the next track ID and Sound in the queue, or the 1st one if nothing is currently playing.

    @within MusicController

    @param track string -- The name of the Sound you're attempting to play.
    @return (trackID number, trackSound Sound) -- Next ID and Sound in queue
]=]
function MusicController:GetTrack(track: string?)
    -- If no track is supplied, gather the next one or the last one so the queue starts at the beignning.
    if not track then
        track = self._trackNames[self._currentTrack or #self._trackNames]
    end

    if track then
        -- Search for a matching track name
        for trackNumber, name in self._trackNames do
            if name == track then
                local nextTrackID = if trackNumber + 1 <= #self._trackNames then trackNumber + 1 else 1
                return nextTrackID, self._trackSounds[nextTrackID]
            end
        end
    else
        -- No track was supplied, return the first one in the queue
        return 1, self._trackSounds[1]
    end

    return nil, nil
end

--[=[
    Play the supplied track, or the next track in the queue.

    @within MusicController

    @param track string -- The name of the Sound you're attempting to play.
]=]
function MusicController:Play(track: string?)
    -- Verify that the music library was populated
    if #self._trackNames == 0 or #self._trackSounds == 0 then
        -- Debug
        if RunService:IsStudio() then
            warn(`Did you forget to Initialize the music folder?`)
        end
        return
    end

    -- Gather information regarding the next track to play
    local trackID, trackSound = self:GetTrack(track)
    if not trackID or not trackSound then
        -- Debug
        if RunService:IsStudio() then
            warn(`failed to play track {track}`)
        end
        return
    end

    -- Stop the current track if one is playing
    if self._currentTrack then
        self:Stop()
    end

    -- Update the current track and play the track
    self._currentTrack = trackID
    self._trackSounds[trackID]:Play()

    -- Handle auto-playing the next track
    if self._autoPlayNextTrack then
        self._nextTrackConnection = self._trackSounds[trackID].Ended:Once(function()
            self:Play()
        end)
    end

    return
end

--[=[
    Pauses the current track if one is playing.

    @within MusicController
]=]
function MusicController:Pause()
    if self._currentTrack then
        self._trackSounds[self._currentTrack]:Pause()
    end

    return
end

--[=[
    Resumes the current track if one is paused.

    @within MusicController
]=]
function MusicController:Resume()
    if not self._currentTrack then
        -- Debug
        if RunService:IsStudio() then
            warn(`failed to resume track`)
        end
        return
    end

    self._trackSounds[self._currentTrack]:Resume()

    return
end

--[=[
    Stops the current track if one is playing. Cleans up additional connections and wipes current track.

    @within MusicController
]=]
function MusicController:Stop()
    if self._currentTrack then
        self._trackSounds[self._currentTrack]:Stop()
    end

    if self._nextTrackConnection and self._nextTrackConnection.Connected then
        self._nextTrackConnection:Disconnect()
    end

    self._currentTrack = nil

    return
end

--[=[
    Skips the current track if one is playing.

    @within MusicController
]=]
function MusicController:Skip()
    if not self._currentTrack then
        -- Debug
        if RunService:IsStudio() then
            warn(`failed to skip track`)
        end
        return
    end

    local nextTrackID = if self._currentTrack + 1 <= #self._trackNames then self._currentTrack + 1 else 1
    local nextTrackName = self._trackNames[nextTrackID]
    self:Play(nextTrackName)

    return
end

return MusicController
