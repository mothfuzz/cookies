//audio interop code
//please use it responsibly
class AudioInterface {

    async reset() {
        this.loadedSounds = [];
        this.playingSounds = [];
        this.playingSoundsFree = [];
        this.musicId = 0;
        this.musicSource = null;
        clearInterval(this.musicFading);
        this.musicFading = null;
        this.musicPlayed = 0;
        this.musicPaused = 0;
        this.musicPlayingFlag = false;
        if(this.ctx) {
            await this.ctx.close();
        }
        this.ctx = new AudioContext();
    }

    constructor(mem) {
        this.mem = mem;
        this.reset();
    }

    getInterface() {
        return {
            "load_sound": (ptr, len) => this.loadSound(ptr, len),
            "play_sound_ptr": (soundId, looped, playingSoundPtr) => this.playSoundPtr(soundId, looped, playingSoundPtr),
            "loop_sound": (playingSoundPtr, looped) => this.loopSound(playingSoundPtr, looped),
            "stop_sound": (playingSoundPtr, finishPlaying) => this.stopSound(playingSoundPtr, finishPlaying),
            "pause_sound": (playingSoundPtr) => this.pauseSound(playingSoundPtr),
            "resume_sound": (playingSoundPtr) => this.resumeSound(playingSoundPtr),
            "load_music": (ptr, len) => this.loadSound(ptr, len),
            "play_music": (soundId, fade) => this.playMusic(soundId, fade),
            "stop_music": (fade) => this.stopMusic(fade),
            "pause_music": (fade) => this.pauseMusic(fade),
            "resume_music": (fade) => this.resumeMusic(fade),
            "queue_music": (newMusicId, fadeOut, fadeIn) => this.queueMusic(newMusicId, fadeOut, fadeIn),
            "music_playing": () => this.musicPlaying(),
        };
    }

    //recreates a source node on the specified playingSound and then plays it.
    //this is necessary because AudioBufferSourceNodes can only be start()ed once.
    initPlayingSound(id) {
        let snd = this.playingSounds[id-1];
        //the sound might not be loaded, but the function will return anyway because of async.
        //so we gotta do a custom callback
        let whenLoaded = new Promise(resolve => {
            const interval = setInterval(() => {
                if (this.loadedSounds[snd.soundId-1]) {
                    clearInterval(interval);
                    resolve();
                }
            }, 1);
        });
        whenLoaded.then(() => {
            let source = this.ctx.createBufferSource();
            source.buffer = this.loadedSounds[snd.soundId-1];
            source.connect(this.ctx.destination);
            source.addEventListener("ended", () => {
                //the ended event is triggered every time it passes the end point even if loop is true, so ignore if that's the case
                //also we want to keep it alive if it was only paused and not stopped
                if(snd.looping || !snd.playing) {
                    return;
                }
                snd.gen += 1;
                snd.source = null;
                this.playingSoundsFree.push(id);
            });
            source.loop = snd.looping;
            if(snd.stopped) {
                snd.started = this.ctx.currentTime - snd.stopped;
                //have to modulo duration because it might be looped several times, which gets clamped,
                //but we want it to start wherever it was paused.
                source.start(0, snd.stopped % snd.source.buffer.duration);
            } else {
                snd.started = this.ctx.currentTime;
                source.start(0);
            }
            snd.source = source;
            snd.playing = true;
        });
    }

    loadSound(filedataPtr, filedataLen) {
        let filedata = this.mem.loadBytes(filedataPtr, filedataLen);
        //decodeAudioData complains about 'detached' memory so copy it over to a pure JS environment.
        let filedata2 = new Uint8Array(filedata);
        this.loadedSounds.push(null);
        const soundId = this.loadedSounds.length;
        this.ctx.decodeAudioData(filedata2.buffer).then((buffer) => {
            this.loadedSounds[soundId-1] = buffer;
        }).catch((e) => {
            console.log(e);
        });
        return soundId;
    }

    playSoundPtr(soundId, looped, playingSoundPtr) {
        if(soundId <= 0 || soundId > this.loadedSounds.length) {
            console.log("sound", soundId, "does not exist");
            return;
        }

        let id = this.playingSoundsFree.pop();
        let gen = 0;
        if(id == undefined) {
            this.playingSounds.push({});
            id = this.playingSounds.length;
        } else {
            gen = this.playingSounds[id-1].gen;
        }

        let snd = this.playingSounds[id-1];
        snd.soundId = soundId;
        snd.id = id;
        snd.gen = gen;
        snd.looping = looped;
        snd.started = 0;
        snd.stopped = 0;
        snd.playing = false;
        this.initPlayingSound(id);

        this.mem.storeU32(playingSoundPtr, id);
        this.mem.storeU16(playingSoundPtr+4, gen);
        this.mem.storeU32(playingSoundPtr+6, soundId);
    }

    loopSound(playingSoundPtr, looped) {
        let id = this.mem.loadU32(playingSoundPtr);
        if(id <= 0 || id > this.playingSounds.length) {
            console.log("sound", id, "does not exist");
            return;
        }
        let gen = this.mem.loadU16(playingSoundPtr+4);
        let snd = this.playingSounds[id-1];
        if(snd.gen != gen) {
            let soundId = this.mem.loadU32(playingSoundPtr+6);
            this.playSoundPtr(soundId, looped, playingSoundPtr);
            return;
        }
        snd.looping = looped;
        snd.source.loop = looped;
    }

    stopSound(playingSoundPtr, finishPlaying) {
        let id = this.mem.loadU32(playingSoundPtr);
        if(id <= 0 || id > this.playingSounds.length) {
            console.log("sound", id, "does not exist");
            return;
        }
        let gen = this.mem.loadU16(playingSoundPtr+4);
        let snd = this.playingSounds[id-1];
        if(snd.gen != gen) {
            return;
        }
        //if already dead don't do anything.
        if(!snd.source) {
            return;
        }
        //disable looping so we can free it once it finishes playing
        snd.looping = false;
        if(finishPlaying) {
            snd.source.loop = false;
        } else {
            snd.source.stop();
        }
    }

    pauseSound(playingSoundPtr) {
        let id = this.mem.loadU32(playingSoundPtr);
        if(id <= 0 || id > this.playingSounds.length) {
            console.log("sound", id, "does not exist");
            return;
        }
        let gen = this.mem.loadU16(playingSoundPtr+4);
        let snd = this.playingSounds[id-1];
        if(snd.gen != gen) {
            return;
        }
        if(!snd.source) {
            return;
        }
        snd.source.stop();
        snd.stopped = this.ctx.currentTime - snd.started;
        snd.playing = false;
    }

    resumeSound(playingSoundPtr) {
        let id = this.mem.loadU32(playingSoundPtr);
        if(id <= 0 || id > this.playingSounds.length) {
            console.log("sound", id, "does not exist");
            return;
        }
        let gen = this.mem.loadU16(playingSoundPtr+4);
        let snd = this.playingSounds[id-1];
        if(snd.gen != gen) {
            let soundId = this.mem.loadU32(playingSoundPtr+6);
            //looping false because that's the only way the sound would have died.
            this.playSoundPtr(soundId, false, playingSoundPtr);
            return;
        }
        if(snd.playing) {
            //so much for that
            return;
        }
        this.initPlayingSound(id);
    }

    playMusic(soundId, fade) {
        this.musicPlayingFlag = true;
        this.musicId = soundId;
        //wait for music to actually load before queuing up further action
        let whenLoaded = new Promise(resolve => {
            const interval = setInterval(() => {
                if (this.loadedSounds[this.musicId-1]) {
                    clearInterval(interval);
                    resolve();
                }
            }, 1);
        });
        whenLoaded.then(() => {
            if(this.musicSource) {
                this.musicSource.stop();
            }
            this.musicSource = this.ctx.createBufferSource();
            this.musicSource.buffer = this.loadedSounds[this.musicId-1];
            this.musicSource.loop = true;
            this.musicSource.start(0);

            this.musicGain = this.ctx.createGain();
            this.musicGain.gain.setValueAtTime(0.0, this.ctx.currentTime);
            this.musicSource.connect(this.musicGain);
            this.musicGain.connect(this.ctx.destination);
            this.musicGain.gain.setValueAtTime(0.0, this.ctx.currentTime);
            this.musicGain.gain.linearRampToValueAtTime(1.0, this.ctx.currentTime + fade/1000);

            this.musicPlayed = this.ctx.currentTime;
            this.musicPaused = 0;
        });
    }
    pauseMusic(fade) {
        if(!this.musicId) {
            return;
        }
        if(!this.loadedSounds[this.musicId-1]) {
            return;
        }
        this.musicPlayingFlag = false;
        if(this.musicFading) {
            return;
        }
        this.musicGain.gain.cancelScheduledValues(this.ctx.currentTime);
        this.musicGain.gain.setValueAtTime(1.0, this.ctx.currentTime);
        this.musicGain.gain.linearRampToValueAtTime(0.0, this.ctx.currentTime + fade/1000);
        this.musicFading = setInterval(() => {
            //(check for presence because audio might have been reset mid-fade)
            if(this.musicSource) {
                this.musicSource.stop();
                this.musicSource = null;
                if(this.musicPlayed > 0) {
                    this.musicPaused = this.ctx.currentTime - this.musicPlayed;
                }
            }
            clearInterval(this.musicFading);
            this.musicFading = null;
        }, fade);
    }
    stopMusic(fade) {
        this.musicPlayed = 0;
        this.musicPaused = 0;
        this.pauseMusic(fade);
    }
    resumeMusic(fade) {
        if(!this.musicId) {
            return;
        }
        if(!this.loadedSounds[this.musicId-1]) {
            //this.playMusic(this.musicId, fade); //it would already be queued to play
            return;
        }

        this.musicPlayingFlag = true;

        //always clear scheduled stops if a play command was issued
        if(this.musicFading) {
            clearInterval(this.musicFading);
            this.musicFading = null;
            //if it was paused/stopped but not finished... simply fade it back in and return
            if(this.musicSource) {
                this.musicGain.gain.cancelScheduledValues(this.ctx.currentTime);
                this.musicGain.gain.setValueAtTime(0.0, this.ctx.currentTime);
                this.musicGain.gain.linearRampToValueAtTime(1.0, this.ctx.currentTime + fade/1000);
                return;
            }
        }

        //otherwise if it was already cleared then we have to recreate the node
        if(!this.musicSource) {
            this.musicSource = this.ctx.createBufferSource();
            this.musicSource.buffer = this.loadedSounds[this.musicId-1];
            this.musicSource.loop = true;
            this.musicSource.start(0, this.musicPaused % this.musicSource.buffer.duration);
            this.musicPlayed = this.ctx.currentTime - this.musicPaused;
            this.musicSource.connect(this.musicGain);
            this.musicGain.gain.cancelScheduledValues(this.ctx.currentTime);
            this.musicGain.gain.setValueAtTime(0.0, this.ctx.currentTime);
            this.musicGain.gain.linearRampToValueAtTime(1.0, this.ctx.currentTime + fade/1000);
        }
    }
    queueMusic(newSoundId, fadeOut, fadeIn) {
        if(!this.musicSource) {
            //skip the fade-out if it's already stopped
            fadeOut = 0;
        }
        this.stopMusic(fadeOut);
        let q = setInterval(() => {
            this.playMusic(newSoundId, fadeIn);
            clearInterval(q);
        }, fadeOut);
    }
    musicPlaying() {
        return this.musicPlayingFlag;
    }
}
