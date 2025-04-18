--!strict

--[[
    MusicController.lua
    Author: Michael S (DevIrradiant)

    Description: Music controller that supports control from client and server. Optional configuration for adjusting cross-fade duration, and auto-play toggle.
]]

-- Services
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Types
type CrossFadeStatus = {
-- Internal
    -- Tween for sound fading out
    FadeOutTween: Tween?,

    -- Connection for once fadeOut has completed
    FadeOutConnection: RBXScriptConnection?,

    -- Tween for sound fading in
    FadeInTween: Tween?,

    -- Connection for once fadeIn has completed
    FadeInConnection: RBXScriptConnection?
}

export type Configuration = {
-- External
    autoPlayNextTrack: boolean,
    crossFadeSeconds: number,
}

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

    -- Time in seconds for songs to cross fade
    _crossFadeSeconds: number,

    -- Connection that will play the next track when currentTrack completes.
    _nextTrackConnection: RBXScriptConnection?,

    _crossFadeStatus: CrossFadeStatus,

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



--[=[
    @class MusicController

    A simple handler for client and server controlled Music.
]=]
local MusicController = {
-- Refs
    _trackNames = {},
    _trackSounds = {},
    _autoPlayNextTrack = true,
    _crossFadeSeconds = 0,

-- State
    _currentTrack = nil,
    _crossFadeStatus = {}
} :: MusicController

--[=[
    Populates the track names and track sounds based on a supplied table of sounds.

    @within MusicController

    @param library {[number]: Sound} -- Supplied table of Sounds to populate the library with
]=]
function MusicController:PopulateLibrary(library: {Sound}, config: Configuration?)
    -- Wipe Library if already populated
    self:Stop()
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

        -- Store original volume data for cross fading
        sound:SetAttribute("OriginalVolume", sound.Volume)
    end

    -- Update configuration
    if config then
        self._autoPlayNextTrack = config.autoPlayNextTrack
        self._crossFadeSeconds = config.crossFadeSeconds
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
    -- Search for a matching track name
    if track then
        for trackNumber, name in self._trackNames do
            if name == track then
                return trackNumber, self._trackSounds[trackNumber]
            end
        end

    -- Otherwise, search for next track in the queue
    else
        -- If no track is supplied, gather the next one, or the last one so the queue starts at the beignning.
        track = if self._currentTrack then self._trackNames[self._currentTrack] else self._trackNames[#self._trackNames]
        for trackNumber, name in self._trackNames do
            if name == track then
                local nextTrackID = if trackNumber + 1 <= #self._trackNames then trackNumber + 1 else 1
                return nextTrackID, self._trackSounds[nextTrackID]
            end
        end
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

    -- Reset sound volume and begin the track
    self._trackSounds[trackID].Volume = 0
    self._trackSounds[trackID]:Play()

    -- Setup Tween
    self._crossFadeStatus.FadeInTween = TweenService:Create(
        self._trackSounds[trackID],
        TweenInfo.new(self._crossFadeSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
        {Volume = self._trackSounds[trackID]:GetAttribute("OriginalVolume")}
    )

    -- Run Tween
    if not self._crossFadeStatus.FadeInTween then
        return
    end
    self._crossFadeStatus.FadeInTween:Play()

    -- Setup connection for once sound has faded in
    self._crossFadeStatus.FadeInConnection = self._crossFadeStatus.FadeInTween.Completed:Once(function()
        self._crossFadeStatus.FadeInTween:Destroy()
    end)

    -- Handle auto-playing the next track
    if self._autoPlayNextTrack then
        self._nextTrackConnection = RunService.Heartbeat:Connect(function()
            -- Begin next track when crossFade threshold is met
            if self._trackSounds[trackID].TimePosition >= self._trackSounds[trackID].TimeLength - self._crossFadeSeconds then
                if self._nextTrackConnection then
                    self._nextTrackConnection:Disconnect()
                end
                self:Play()
            end
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
    -- Utl
    local function beginFade(sound: Sound)
        if not sound then
            return
        end

        -- Setup Tween
        self._crossFadeStatus.FadeOutTween = TweenService:Create(
            sound,
            TweenInfo.new(self._crossFadeSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
            {Volume = 0}
        )

        -- Run Tween
        if not self._crossFadeStatus.FadeOutTween then
            return
        end
        self._crossFadeStatus.FadeOutTween:Play()

        -- Setup connection for once sound has faded out
        self._crossFadeStatus.FadeOutConnection = self._crossFadeStatus.FadeOutTween.Completed:Once(function()
            self._crossFadeStatus.FadeOutTween:Destroy()

            sound:Stop()

            -- Determine if a new track has began. If not, reset currentTrack
            local soundID = table.find(self._trackNames, sound.Name)
            if not soundID then
                -- Debug
                if RunService:IsStudio() then
                    warn(`failed to locate soundID`)
                end
                return
            end

            if soundID == self._currentTrack then
                self._currentTrack = nil
            end
        end)
    end

    -- If a sound is already fading out, terminate this as we need to now fade out the sound attempting to fade in
    if self._crossFadeStatus.FadeOutTween and self._crossFadeStatus.FadeOutTween.PlaybackState == Enum.PlaybackState.Playing then
        -- Cleanup connection
        if self._crossFadeStatus.FadeOutConnection and self._crossFadeStatus.FadeOutConnection.Connected then
            self._crossFadeStatus.FadeOutConnection:Disconnect()
        end

        -- Clean up tween and stop the sound
        self._crossFadeStatus.FadeOutTween:Cancel()
        local fadeOutSound = self._crossFadeStatus.FadeOutTween.Instance :: Sound
        fadeOutSound:Stop()
        self._crossFadeStatus.FadeOutTween:Destroy()
    end

    -- If a sound is already fading in, terminate this and fade out the sound
    if self._crossFadeStatus.FadeInTween and self._crossFadeStatus.FadeInTween.PlaybackState == Enum.PlaybackState.Playing then
        -- Cleanup connection
        if self._crossFadeStatus.FadeInConnection and self._crossFadeStatus.FadeInConnection.Connected then
            self._crossFadeStatus.FadeInConnection:Disconnect()
        end

        -- Clean up the tween and begin fading in
        self._crossFadeStatus.FadeInTween:Cancel()
        beginFade(self._crossFadeStatus.FadeInTween.Instance :: Sound)
        self._crossFadeStatus.FadeInTween:Destroy()

    -- Otherwise, just begin fade out the sound currently playing
    elseif self._currentTrack then
        beginFade(self._trackSounds[self._currentTrack])
    end

    -- Clean up nextTrackConnection
    if self._nextTrackConnection and self._nextTrackConnection.Connected then
        self._nextTrackConnection:Disconnect()
    end

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

    self:Play()

    return
end

return MusicController
