package objects;

import backend.animation.PsychAnimationController;

import flixel.util.FlxSort;
import flixel.util.FlxDestroyUtil;

import openfl.utils.AssetType;
import openfl.utils.Assets;
import openfl.display.MovieClip;
import openfl.display.Loader;
import openfl.utils.ByteArray;
import openfl.events.Event;
import openfl.display.FrameLabel;

import haxe.Json;
import sys.io.File;
import sys.FileSystem;
import haxe.zip.Reader;

import backend.Song;
import states.stages.objects.TankmenBG;

typedef CharacterFile = {
	var animations:Array<AnimArray>;
	var image:String;
	var scale:Float;
	var sing_duration:Float;
	var healthicon:String;

	var position:Array<Float>;
	var camera_position:Array<Float>;

	var flip_x:Bool;
	var no_antialiasing:Bool;
	var healthbar_colors:Array<Int>;
	var vocals_file:String;
	@:optional var _editor_isPlayer:Null<Bool>;
}

typedef AnimArray = {
	var anim:String;
	var name:String;
	var fps:Int;
	var loop:Bool;
	var indices:Array<Int>;
	var offsets:Array<Int>;
}

class Character extends FlxSprite
{
	public static final DEFAULT_CHARACTER:String = 'bf';

	public var animOffsets:Map<String, Array<Dynamic>>;
	public var debugMode:Bool = false;
	public var extraData:Map<String, Dynamic> = new Map<String, Dynamic>();

	public var isPlayer:Bool = false;
	public var curCharacter:String = DEFAULT_CHARACTER;

	public var holdTimer:Float = 0;
	public var heyTimer:Float = 0;
	public var specialAnim:Bool = false;
	public var animationNotes:Array<Dynamic> = [];
	public var stunned:Bool = false;
	public var singDuration:Float = 4;
	public var idleSuffix:String = '';
	public var danceIdle:Bool = false;
	public var skipDance:Bool = false;

	public var healthIcon:String = 'face';
	public var animationsArray:Array<AnimArray> = [];

	public var positionArray:Array<Float> = [0, 0];
	public var cameraPosition:Array<Float> = [0, 0];
	public var healthColorArray:Array<Int> = [255, 0, 0];

	public var missingCharacter:Bool = false;
	public var missingText:FlxText;
	public var hasMissAnimations:Bool = false;
	public var vocalsFile:String = '';

	public var imageFile:String = '';
	public var jsonScale:Float = 1;
	public var noAntialiasing:Bool = false;
	public var originalFlipX:Bool = false;
	public var editorIsPlayer:Null<Bool> = null;

	// SWF / ZIP support
	public var isSWF:Bool = false;
	public var swfClip:MovieClip;
	public var swfLabels:Map<String, FrameLabel> = new Map();
	public var isZipped:Bool = false;
	public var zipExtractPath:String = '';

	public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false)
	{
		super(x, y);
		animation = new PsychAnimationController(this);
		animOffsets = new Map<String, Array<Dynamic>>();
		this.isPlayer = isPlayer;
		changeCharacter(character);
		
		switch(curCharacter)
		{
			case 'pico-speaker':
				skipDance = true;
				loadMappedAnims();
				playAnim("shoot1");
			case 'pico-blazin', 'darnell-blazin':
				skipDance = true;
		}
	}

	public function changeCharacter(character:String)
	{
		animationsArray = [];
		animOffsets = [];
		curCharacter = character;
		var characterPath:String = 'characters/$character.json';

		var path:String = Paths.getPath(characterPath, TEXT);
		#if MODS_ALLOWED
		if (!FileSystem.exists(path))
		#else
		if (!Assets.exists(path))
		{
			path = Paths.getSharedPath('characters/' + DEFAULT_CHARACTER + '.json');
			missingCharacter = true;
			missingText = new FlxText(0, 0, 300, 'ERROR:\n$character.json', 16);
			missingText.alignment = CENTER;
		}
		#end

		try
		{
			#if MODS_ALLOWED
			loadCharacterFile(Json.parse(File.getContent(path)));
			#else
			loadCharacterFile(Json.parse(Assets.getText(path)));
			#end
		}

		skipDance = false;
		hasMissAnimations = hasAnimation('singLEFTmiss') || hasAnimation('singDOWNmiss') || hasAnimation('singUPmiss') || hasAnimation('singRIGHTmiss');
		recalculateDanceIdle();
		dance();
	}

	public function loadCharacterFile(json:Dynamic)
	{
		isAnimateAtlas = false;
		isSWF = false;
		isZipped = false;

		// Detect formats
		var zipPath:String = Paths.getPath('images/' + json.image + '.zip', BINARY);
		var animZipPath:String = Paths.getPath('images/' + json.image + '.anim.zip', BINARY);
		var swfPath:String = Paths.getPath('images/' + json.image + '.swf', BINARY);

		#if MODS_ALLOWED
		if(FileSystem.exists(animZipPath)) { isZipped = true; zipPath = animZipPath; }
		else if(FileSystem.exists(zipPath)) { isZipped = true; }
		else if(FileSystem.exists(swfPath)) { isSWF = true; }
		#else
		if(Assets.exists(animZipPath)) { isZipped = true; zipPath = animZipPath; }
		else if(Assets.exists(zipPath)) { isZipped = true; }
		else if(Assets.exists(swfPath)) { isSWF = true; }
		#end

		// ZIP extraction
		if(isZipped)
		{
			zipExtractPath = 'mods/temp/' + json.image + '/';
			#if MODS_ALLOWED
			if(!FileSystem.exists(zipExtractPath))
				FileSystem.createDirectory(zipExtractPath);

			var bytes = ByteArray.fromFile(zipPath);
			var reader = new Reader(bytes);
			var files = reader.read();
			for(f in files)
			{
				if(f.fileName != null && f.fileName.length > 0)
				{
					var targetPath = zipExtractPath + f.fileName;
					var dir = targetPath.substr(0, targetPath.lastIndexOf('/'));
					if(!FileSystem.exists(dir)) FileSystem.createDirectory(dir);

					var data = f.data;
					if(data != null)
						File.saveBytes(targetPath, data);
				}
			}
			#end

			var jsonInside = zipExtractPath + json.image + '.json';
			if(FileSystem.exists(jsonInside))
			{
				loadCharacterFile(Json.parse(File.getContent(jsonInside)));
				return;
			}
		}

		// SWF loading
		if(isSWF)
		{
			var bytes:ByteArray;
			#if MODS_ALLOWED
			bytes = ByteArray.fromFile(swfPath);
			#else
			bytes = Assets.getBytes('images/' + json.image + '.swf');
			#end

			var loader = new Loader();
			loader.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
				swfClip = cast(loader.content, MovieClip);
				addChild(swfClip);
				swfClip.play();

				// Map SWF frame labels for FNF animation control
				for (label in swfClip.currentLabels)
					swfLabels.set(label.name.toLowerCase(), label);
			});
			loader.loadBytes(bytes);
		}

		#if flxanimate
		var animToFind:String = Paths.getPath('images/' + json.image + '/Animation.json', TEXT);
		if (#if MODS_ALLOWED FileSystem.exists(animToFind) || #end Assets.exists(animToFind))
			isAnimateAtlas = true;
		#end

		scale.set(1, 1);
		updateHitbox();

		if(!isAnimateAtlas && !isSWF)
			frames = Paths.getMultiAtlas(json.image.split(','));

		#if flxanimate
		else if(isAnimateAtlas)
		{
			atlas = new FlxAnimate();
			atlas.showPivot = false;
			try
				Paths.loadAnimateAtlas(atlas, json.image);
			catch(e:haxe.Exception)
				trace('Could not load atlas ${json.image}: $e');
		}
		#end

		imageFile = json.image;
		jsonScale = json.scale;
		if(json.scale != 1) {
			scale.set(jsonScale, jsonScale);
			updateHitbox();
		}

		positionArray = json.position;
		cameraPosition = json.camera_position;
		healthIcon = json.healthicon;
		singDuration = json.sing_duration;
		flipX = (json.flip_x != isPlayer);
		healthColorArray = (json.healthbar_colors != null && json.healthbar_colors.length > 2) ? json.healthbar_colors : [161, 161, 161];
		vocalsFile = json.vocals_file != null ? json.vocals_file : '';
		originalFlipX = (json.flip_x == true);
		editorIsPlayer = json._editor_isPlayer;

		noAntialiasing = (json.no_antialiasing == true);
		antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

		animationsArray = json.animations;
		if(animationsArray != null && animationsArray.length > 0)
		{
			for (anim in animationsArray)
			{
				var animAnim:String = '' + anim.anim;
				var animName:String = '' + anim.name;
				var animFps:Int = anim.fps;
				var animLoop:Bool = !!anim.loop;
				var animIndices:Array<Int> = anim.indices;

				if(!isAnimateAtlas && !isSWF)
				{
					if(animIndices != null && animIndices.length > 0)
						animation.addByIndices(animAnim, animName, animIndices, "", animFps, animLoop);
					else
						animation.addByPrefix(animAnim, animName, animFps, animLoop);
				}
				#if flxanimate
				else if(isAnimateAtlas)
				{
					if(animIndices != null && animIndices.length > 0)
						atlas.anim.addBySymbolIndices(animAnim, animName, animIndices, animFps, animLoop);
					else
						atlas.anim.addBySymbol(animAnim, animName, animFps, animLoop);
				}
				#end

				if(anim.offsets != null && anim.offsets.length > 1)
					addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
				else
					addOffset(anim.anim, 0, 0);
			}
		}
		#if flxanimate
		if(isAnimateAtlas) copyAtlasValues();
		#end
	}

	// SWF-aware playAnim
	public override function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void
	{
		if(isSWF && swfClip != null)
		{
			var label = swfLabels.get(AnimName.toLowerCase());
			if(label != null)
				swfClip.gotoAndPlay(label.frame);
			else
				swfClip.gotoAndPlay(1);
			return;
		}

		super.playAnim(AnimName, Force, Reversed, Frame);
	}

	override function update(elapsed:Float)
	{
		if(isSWF && swfClip != null)
		{
			swfClip.x = x;
			swfClip.y = y;
			swfClip.scaleX = scale.x;
			swfClip.scaleY = scale.y;
			swfClip.rotation = angle;
			return;
		}
		if(isAnimateAtlas) atlas.update(elapsed);
		super.update(elapsed);
	}

	public override function draw()
	{
		if(isSWF && swfClip != null) return;
		super.draw();
	}

	public override function destroy()
	{
		if(isSWF && swfClip != null)
		{
			removeChild(swfClip);
			swfClip = null;
			swfLabels = new Map();
		}

		if(isZipped && FileSystem.exists(zipExtractPath))
		{
			for(file in FileSystem.readDirectory(zipExtractPath))
			{
				var full = zipExtractPath + file;
				if(FileSystem.isDirectory(full))
				{
					for(sub in FileSystem.readDirectory(full))
						FileSystem.deleteFile(full + '/' + sub);
					FileSystem.deleteDirectory(full);
				}
				else
					FileSystem.deleteFile(full);
			}
			FileSystem.deleteDirectory(zipExtractPath);
		}

		atlas = FlxDestroyUtil.destroy(atlas);
		super.destroy();
	}
}
