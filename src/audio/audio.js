//audio interop code
//please use it responsibly
class AudioInterface {

    async reset() {
        this.loadedSounds = [];
        this.playingSounds = [];
        this.freeSounds = [];
        if(this.ctx) {
            await this.ctx.close();
        }
        this.ctx = new AudioContext();
    }

    quit() {
        for(let sound of this.playingSounds) {
            sound.source.stop(0);
        }
    }

    constructor(mem) {
        this.mem = mem;
        this.reset();
    }

    getInterface() {
        return {
            "make_sound_from_file": (ptr, len) => this.makeSoundFromFile(ptr, len),
            "delete_sound": (soundId) => this.deleteSound(soundId),
            "play_sound_ptr": (soundId, looped, fadeIn, playingSoundPtr) => this.playSoundPtr(soundId, looped, fadeIn, playingSoundPtr),
            "loop_sound": (playingSoundPtr, looped) => this.loopSound(playingSoundPtr, looped),
            "sound_is_looping": (playingSoundPtr) => this.soundIsLooping(playingSoundPtr),
            "stop_sound": (playingSoundPtr, finishPlaying) => this.stopSound(playingSoundPtr, finishPlaying),
            "sound_is_playing": (playingSoundPtr) => this.soundIsPlaying(playingSoundPtr),
            "pause_sound": (playingSoundPtr, fadeOut) => this.pauseSound(playingSoundPtr, fadeOut),
            "resume_sound": (playingSoundPtr, fadeIn) => this.resumeSound(playingSoundPtr, fadeIn),
            "quit": () => this.quit(),
        };
    }

    makeSoundFromFile(filedataPtr, filedataLen) {
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

    deleteSound(soundId) {
        delete this.loadedSounds[soundId-1];
    }

    deletePlayingSound(snd) {
        //console.log("deleting playing sound...");
        snd.gen += 1;
        this.freeSounds.push(snd.id);
    }

    //recreates a source node on the specified playingSound and then plays it.
    //this is necessary because AudioBufferSourceNodes can only be start()ed once.
    //assumes id is valid, etc.
    startSound(id, fadeIn) {
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
            snd.source = this.ctx.createBufferSource();
            snd.source.loop = snd.looping;
            snd.source.buffer = this.loadedSounds[snd.soundId-1];
            //snd.source.connect(this.ctx.destination);
            snd.gain = this.ctx.createGain();
            snd.gain.gain.setValueAtTime(0.0, this.ctx.currentTime);
            snd.source.connect(snd.gain);
            snd.gain.connect(this.ctx.destination);
            snd.gain.gain.setValueAtTime(0.0, this.ctx.currentTime);
            snd.gain.gain.linearRampToValueAtTime(1.0, this.ctx.currentTime + fadeIn/1000);
            snd.source.addEventListener("ended", () => {
                //console.log("end listener called!");
                //the ended event is triggered every time it passes the end point even if loop is true, so ignore if that's the case
                //also we want to keep it alive if it was only paused and not stopped
                if(snd.looping || snd.stopped > 0) {
                    return;
                }
                this.deletePlayingSound(snd);
            });
            if(snd.stopped) {
                snd.started = this.ctx.currentTime - snd.stopped;
                //have to modulo duration because it might be looped several times, which gets clamped,
                //but we want it to start wherever it was paused.
                snd.source.start(0, snd.stopped % snd.source.buffer.duration);
            } else {
                snd.started = this.ctx.currentTime;
                snd.source.start(0);
            }
            snd.playing = true;
        });
    }

    playSoundPtr(soundId, looped, fadeIn, playingSoundPtr) {
        if(soundId <= 0 || soundId > this.loadedSounds.length) {
            console.log("sound", soundId, "does not exist");
            return;
        }

        let id = this.freeSounds.pop();
        let gen = 0;
        if(id != undefined) {
            gen = this.playingSounds[id-1].gen;
        } else {
            this.playingSounds.push({});
            id = this.playingSounds.length;
        }

        let snd = this.playingSounds[id-1];
        snd.soundId = soundId;
        snd.id = id;
        snd.gen = gen;
        snd.looping = looped;
        snd.started = 0;
        snd.stopped = 0;
        snd.playing = false;
        this.startSound(id, fadeIn);

        this.mem.storeU32(playingSoundPtr, id);
        this.mem.storeU16(playingSoundPtr+4, gen);
        this.mem.storeU32(playingSoundPtr+6, soundId);
    }

    getPlayingSound(playingSoundPtr) {
        let id = this.mem.loadU32(playingSoundPtr);
        if(id <= 0 || id > this.playingSounds.length) {
            console.log("sound", id, "does not exist");
            return;
        }
        let gen = this.mem.loadU16(playingSoundPtr+4);
        let snd = this.playingSounds[id-1];
        if(snd.gen != gen) {
            return undefined;
        }
        return snd;
    }

    loopSound(playingSoundPtr, looped) {
        let snd = this.getPlayingSound(playingSoundPtr);
        if(snd) {
            snd.looping = looped;
            snd.source.loop = looped;
        } else {
            let soundId = this.mem.loadU32(playingSoundPtr+6);
            this.playSoundPtr(soundId, looped, playingSoundPtr);
        }

    }

    soundIsLooping(playingSoundPtr) {
        let snd = this.getPlayingSound(playingSoundPtr);
        if(snd && snd.looping) {
            return true;
        }
        return false;
    }

    stopSound(playingSoundPtr, finishPlaying) {
        let snd = this.getPlayingSound(playingSoundPtr);
        if(snd) {
            if(!snd.playing) {
                this.deletePlayingSound(snd);
            }
            snd.started = 0;
            snd.stopped = 0;
            snd.playing = false;
            snd.looping = false;
            if(finishPlaying) {
                snd.source.loop = false;
            } else {
                snd.source.stop();
            }
        }
    }

    soundIsPlaying(playingSoundPtr) {
        let snd = this.getPlayingSound(playingSoundPtr);
        if(snd && snd.playing) {
            return true;
        }
        return false;
    }

    pauseSound(playingSoundPtr, fadeOut) {
        let snd = this.getPlayingSound(playingSoundPtr);
        if(snd) {
            snd.gain.gain.cancelScheduledValues(this.ctx.currentTime);
            snd.gain.gain.setValueAtTime(1.0, this.ctx.currentTime);
            snd.gain.gain.linearRampToValueAtTime(0.0, this.ctx.currentTime + fadeOut/1000);
            let fading = setInterval(() => {
                //(check for presence because audio might have been reset mid-fade)
                if(snd.source) {
                    snd.source.stop();
                    snd.stopped = this.ctx.currentTime - snd.started;
                    snd.playing = false;
                }
                clearInterval(fading);
            }, fadeOut);
        }
    }

    resumeSound(playingSoundPtr, fadeIn) {
        let snd = this.getPlayingSound(playingSoundPtr);
        if(snd) {
            if(snd.playing) {
                return
            }
            this.startSound(snd.id, fadeIn)
        } else {
            let soundId = this.mem.loadU32(playingSoundPtr+6);
            //looping false because that's the only way the sound would have died.
            this.playSoundPtr(soundId, false, fadeIn, playingSoundPtr);
        }
    }
}
