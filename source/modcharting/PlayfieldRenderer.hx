package modcharting;

import modcharting.BezierPathTween;
import modcharting.BezierPathNumTween;
import flixel.util.FlxTimer.FlxTimerManager;
import flixel.math.FlxMath;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxColor;
import flixel.FlxStrip;
import flixel.graphics.tile.FlxDrawTrianglesItem.DrawData;
import openfl.geom.Vector3D;
import flixel.util.FlxSpriteUtil;
import flixel.graphics.frames.FlxFrame;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.FlxSprite;
import flixel.FlxG;
import modcharting.Modifier;
import flixel.system.FlxAssets.FlxShader;
import modcharting.TweenManager;
#if LEATHER
import states.PlayState;
import game.Note;
import game.StrumNote;
import game.Conductor;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import states.PlayState;
import objects.Note;
import objects.StrumNote;
#else
import PlayState;
import Note;
import StrumNote;
#end

using StringTools;

// a few todos im gonna leave here:
// setup quaternions for everything else (incoming angles and the rotate mod)
// do add and remove buttons on stacked events in editor
// fix switching event type in editor so you can actually do set events
// finish setting up tooltips in editor
// start documenting more stuff idk

typedef StrumNoteType = #if (PSYCH || LEATHER) StrumNote #elseif KADE StaticArrow #elseif FOREVER_LEGACY UIStaticArrow #elseif ANDROMEDA Receptor #else FlxSprite #end;

class PlayfieldRenderer extends FlxSprite // extending flxsprite just so i can edit draw
{
	public var strumGroup:FlxTypedGroup<StrumNoteType>;
	public var notes:FlxTypedGroup<Note>;
	public var instance:ModchartMusicBeatState;
	public var playStateInstance:PlayState;
	public var playfields:Array<Playfield> = []; // adding an extra playfield will add 1 for each player

	public var eventManager:ModchartEventManager;
	public var modifierTable:ModTable;
	public var tweenManager:TweenManager = null;
	public var timerManager:FlxTimerManager = null;

	public var modchart:ModchartFile;
	public var inEditor:Bool = false;
	public var editorPaused:Bool = false;

	public var speed:Float = 1.0;

	public var modifiers(get, default):Map<String, Modifier>;

	private function get_modifiers():Map<String, Modifier> {
		return modifierTable.modifiers; // back compat with lua modcharts
	}

	public function new(strumGroup:FlxTypedGroup<StrumNoteType>, notes:FlxTypedGroup<Note>, instance:ModchartMusicBeatState) {
		super(0, 0);
		this.strumGroup = strumGroup;
		this.notes = notes;
		this.instance = instance;
		if (instance is PlayState)
			playStateInstance = cast instance; // so it just casts once

		strumGroup.visible = false; // drawing with renderer instead
		notes.visible = false;

		// fix stupid crash because the renderer in playstate is still technically null at this point and its needed for json loading
		instance.playfieldRenderer = this;

		tweenManager = new TweenManager();
		timerManager = new FlxTimerManager();
		eventManager = new ModchartEventManager(this);
		modifierTable = new ModTable(instance, this);
		addNewPlayfield(0, 0, 0);
		modchart = new ModchartFile(this);
	}

	public inline function addNewPlayfield(?x:Float = 0, ?y:Float = 0, ?z:Float = 0, ?alpha:Float = 1) {
		playfields.push(new Playfield(x, y, z, alpha));
	}

	override function update(elapsed:Float) {
		try {
			eventManager.update(elapsed);
			tweenManager.update(elapsed); // should be automatically paused when you pause in game
			timerManager.update(elapsed);
		} catch (e) {
			trace(e);
		}
		super.update(elapsed);
	}

	override public function draw() {
		if (alpha <= 0.001 || !visible)
			return;

		strumGroup.cameras = this.cameras;
		notes.cameras = this.cameras;

		try {
			drawStuff(getNotePositions());
		} catch (e) {
			trace(e);
		}
		// draw notes to screen
	}

	public function addDataToStrum(strumData:NotePositionData, strum:StrumNoteType) {
		strum.x = strumData.x;
		strum.y = strumData.y;
		// Add Z to your strumNoteType if you want it youself!
		// strum.z = strumData.z;
		strum.angle3D.x = strumData.angleX;
		strum.angle3D.y = strumData.angleY;
		strum.angle3D.z = strumData.angleZ;
		strum.scale.x = strumData.scaleX;
		strum.scale.y = strumData.scaleY;
		strum.skew.x = strumData.skewX;
		strum.skew.y = strumData.skewY;
		strum.setColorTransform(1, 1, 1, strumData.alpha, strumData.redOffset, strumData.greenOffset, strumData.blueOffset);
	}

	public function getDataForStrum(i:Int, pf:Int) {
		var strumX = NoteMovement.defaultStrumX[i];
		var strumY = NoteMovement.defaultStrumY[i];
		var strumZ = 0;
		var strumScaleX = NoteMovement.defaultScale[i];
		var strumScaleY = NoteMovement.defaultScale[i];
		var strumSkewX = NoteMovement.defaultSkewX[i];
		var strumSkewY = NoteMovement.defaultSkewY[i];
		var strumData:NotePositionData = NotePositionData.get();
		strumData.setupStrum(strumX, strumY, strumZ, i, strumScaleX, strumScaleY, strumSkewX, strumSkewY, pf);
		playfields[pf].applyOffsets(strumData);
		modifierTable.applyStrumMods(strumData, i, pf);
		return strumData;
	}

	public function addDataToNote(noteData:NotePositionData, daNote:Note) {
		daNote.x = noteData.x;
		daNote.y = noteData.y;
		daNote.z = noteData.z;
		daNote.angle3D.x = noteData.angleX;
		daNote.angle3D.y = noteData.angleY;
		daNote.angle3D.z = noteData.angleZ;
		daNote.scale.x = noteData.scaleX;
		daNote.scale.y = noteData.scaleY;
		daNote.skew.x = noteData.skewX;
		daNote.skew.y = noteData.skewY;
		daNote.setColorTransform(1, 1, 1, noteData.alpha, noteData.redOffset, noteData.greenOffset, noteData.blueOffset);
	}

	public function createDataFromNote(noteIndex:Int, playfieldIndex:Int, curPos:Float, noteDist:Float, incomingAngle:Array<Float>) {
		var noteX = notes.members[noteIndex].x;
		var noteY = notes.members[noteIndex].y;
		var noteZ = notes.members[noteIndex].z;
		var lane = getLane(noteIndex);
		var noteScaleX = NoteMovement.defaultScale[lane];
		var noteScaleY = NoteMovement.defaultScale[lane];
		var noteSkewX = notes.members[noteIndex].skew.x;
		var noteSkewY = notes.members[noteIndex].skew.y;

		var noteAlpha:Float = #if PSYCH notes.members[noteIndex].multAlpha; #else notes.members[noteIndex].isSustainNote ? 0.6 : 1; #end

		var noteData:NotePositionData = NotePositionData.get();
		noteData.setupNote(noteX, noteY, noteZ, lane, noteScaleX, noteScaleY, noteSkewX, noteSkewY, playfieldIndex, noteAlpha, curPos, noteDist,
			incomingAngle[0], incomingAngle[1], notes.members[noteIndex].strumTime, noteIndex);
		playfields[playfieldIndex].applyOffsets(noteData);
		return noteData;
	}

	public function getNoteCurPos(noteIndex:Int, strumTimeOffset:Float = 0) {
		if (notes.members[noteIndex].isSustainNote && !ModchartUtil.getDownscroll(instance))
			strumTimeOffset += Conductor.stepCrochet; // fix upscroll lol
		var distance = (Conductor.songPosition - notes.members[noteIndex].strumTime) + strumTimeOffset;
		return distance * notes.members[noteIndex].speed;
	}

	public inline function getLane(noteIndex:Int) {
		return (notes.members[noteIndex].mustPress ? notes.members[noteIndex].noteData + NoteMovement.keyCount : notes.members[noteIndex].noteData);
	}

	public function getNoteDist(noteIndex:Int) {
		var noteDist = -0.45;
		if (ModchartUtil.getDownscroll(instance))
			noteDist *= -1;
		return noteDist;
	}

	public function getNotePositions() {
		var notePositions:Array<NotePositionData> = [];
		for (pf in 0...playfields.length) {
			for (i in 0...strumGroup.members.length) {
				var strumData = getDataForStrum(i, pf);
				notePositions.push(strumData);
			}
			for (i in 0...notes.members.length) {
				var songSpeed = notes.members[i].speed;

				var lane = getLane(i);

				var noteDist = getNoteDist(i);
				noteDist = modifierTable.applyNoteDistMods(noteDist, lane, pf);

				var sustainTimeThingy:Float = 0;

				// just causes too many issues lol, might fix it at some point
				/*if (notes.members[i].animation.curAnim.name.endsWith('end') && ClientPrefs.downScroll)
					{
						if (noteDist > 0)
							sustainTimeThingy = (NoteMovement.getFakeCrochet()/4)/2; //fix stretched sustain ends (downscroll)
						//else 
							//sustainTimeThingy = (-NoteMovement.getFakeCrochet()/4)/songSpeed;
				}*/

				var curPos = getNoteCurPos(i, sustainTimeThingy);
				curPos = modifierTable.applyCurPosMods(lane, curPos, pf);

				if ((notes.members[i].wasGoodHit || (notes.members[i].prevNote.wasGoodHit))
					&& curPos >= 0
					&& notes.members[i].isSustainNote)
					curPos = 0; // sustain clip

				var incomingAngle:Array<Float> = modifierTable.applyIncomingAngleMods(lane, curPos, pf);
				if (noteDist < 0)
					incomingAngle[0] += 180; // make it match for both scrolls

				// get the general note path
				NoteMovement.setNotePath(notes.members[i], lane, songSpeed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);

				// save the position data
				var noteData = createDataFromNote(i, pf, curPos, noteDist, incomingAngle);

				// add offsets to data with modifiers
				modifierTable.applyNoteMods(noteData, lane, curPos, pf);

				// add position data to list
				notePositions.push(noteData);
			}
		}
		// sort by z before drawing
		notePositions.sort(function(a, b) {
			if (a.z < b.z)
				return -1;
			else if (a.z > b.z)
				return 1;
			else
				return 0;
		});
		return notePositions;
	}

	public function drawStrum(noteData:NotePositionData) {
		if (noteData.alpha <= 0)
			return;
		var changeX:Bool = ((noteData.z > 0 || noteData.z < 0) && noteData.z != 0);
		var strumNote = strumGroup.members[noteData.index];
		var thisNotePos = changeX ? ModchartUtil.calculatePerspective(new Vector3D(noteData.x + (strumNote.width / 2), noteData.y + (strumNote.height / 2),
			noteData.z * 0.001),
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(strumNote.width / 2),
			-(strumNote.height / 2)) : new Vector3D(noteData.x, noteData.y, 0);

		noteData.x = thisNotePos.x;
		noteData.y = thisNotePos.y;
		if (changeX) {
			noteData.scaleX *= (1 / -thisNotePos.z);
			noteData.scaleY *= (1 / -thisNotePos.z);
		}
		// noteData.skewX = skewX + noteData.skewX;
		// noteData.skewY = skewY + noteData.skewY;

		addDataToStrum(noteData, strumGroup.members[noteData.index]); // set position and stuff before drawing
		strumGroup.members[noteData.index].cameras = this.cameras;

		strumGroup.members[noteData.index].draw();
	}

	public function drawNote(noteData:NotePositionData) {
		if (noteData.alpha <= 0.001 || !visible || alpha <= 0.001)
			return;
	
		var changeX:Bool = ((noteData.z > 0 || noteData.z < 0) && noteData.z != 0);
		var daNote = notes.members[noteData.index];
		var thisNotePos = changeX ? ModchartUtil.calculatePerspective(new Vector3D(noteData.x
			+ (daNote.width / 2)
			+ ModchartUtil.getNoteOffsetX(daNote, instance), noteData.y
			+ (daNote.height / 2), noteData.z * 0.001),
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(daNote.width / 2),
			-(daNote.height / 2)) : new Vector3D(noteData.x, noteData.y, 0);
		
		if(daNote.isSustainNote){
			if(!changeX){
				thisNotePos.x += daNote.width;
			}
			if(!daNote.animation.curAnim.name.endsWith("end")){
				noteData.scaleY *= Conductor.stepCrochet / 100 * 1.5 * daNote.speed;
			}
		}

		noteData.x = thisNotePos.x;
		noteData.y = thisNotePos.y;
		if (changeX) {
			noteData.scaleX *= (1 / -thisNotePos.z);
			noteData.scaleY *= (1 / -thisNotePos.z);
		}
		// noteData.skewX = skewX + noteData.skewX;
		// noteData.skewY = skewY + noteData.skewY;
		// set note position using the position data
		addDataToNote(noteData, daNote);
		// make sure it draws on the correct camera
		daNote.cameras = this.cameras;
		// draw it
		daNote.draw();
	}

	public function drawSustainNote(noteData:NotePositionData) {
		if (noteData.alpha <= 0.001 || !visible || alpha <= 0.001)
			return;
		if(utilities.Options.getData("optimizedModcharts")){
			drawNote(noteData);
			return;
		}
		var daNote = notes.members[noteData.index];
		if (daNote.mesh == null)
			daNote.mesh = new SustainStrip(daNote);

		daNote.mesh.scrollFactor.x = daNote.scrollFactor.x;
		daNote.mesh.scrollFactor.y = daNote.scrollFactor.y;
		daNote.alpha = noteData.alpha;
		daNote.mesh.setColorTransform(1, 1, 1, daNote.alpha, noteData.redOffset, noteData.greenOffset, noteData.blueOffset);

		var songSpeed = daNote.speed;
		var lane = noteData.lane;

		// makes the sustain match the center of the parent note when at weird angles
		var yOffsetThingy = (NoteMovement.arrowSizes[lane] / 2);

		var thisNotePos = ModchartUtil.calculatePerspective(new Vector3D(noteData.x
			+ (daNote.width / 2)
			+ ModchartUtil.getNoteOffsetX(daNote, instance),
			noteData.y
			+ ((NoteMovement.arrowSizes[noteData.lane] / 2)), noteData.z * 0.001),
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(daNote.width / 2), yOffsetThingy
			- (NoteMovement.arrowSizes[noteData.lane] / 2));

		var timeToNextSustain = ModchartUtil.getFakeCrochet() / 4;
		if (noteData.noteDist < 0)
			timeToNextSustain *= -1; // weird shit that fixes upscroll lol
		// timeToNextSustain = -ModchartUtil.getFakeCrochet()/4; //weird shit that fixes upscroll lol

		#if (PSYCH && !(PSYCHVERSION >= "0.7"))
		var nextHalfNotePos = getSustainPoint(noteData, timeToNextSustain * 0.5);
		var nextNotePos = getSustainPoint(noteData, timeToNextSustain);
		#else
		var nextHalfNotePos = ModchartUtil.getDownscroll(instance) ? getSustainPoint(noteData,
			timeToNextSustain * 0.458) : getSustainPoint(noteData, timeToNextSustain * 0.548);
		var nextNotePos = ModchartUtil.getDownscroll(instance) ? getSustainPoint(noteData,
			timeToNextSustain + 2.2) : getSustainPoint(noteData, timeToNextSustain - 2.2);
		#end

		var flipGraphic = false;

		// mod/bound to 360, add 360 for negative angles, mod again just in case
		var fixedAngY = ((noteData.incomingAngleY % 360) + 360) % 360;

		var reverseClip = (fixedAngY > 90 && fixedAngY < 270);

		if (noteData.noteDist > 0) // downscroll
		{
			if (!ModchartUtil.getDownscroll(instance)) // fix reverse
				flipGraphic = true;
		} else {
			if (ModchartUtil.getDownscroll(instance))
				flipGraphic = true;
		}
		// render that shit
		daNote.mesh.constructVertices(noteData, thisNotePos, nextHalfNotePos, nextNotePos, flipGraphic, reverseClip);

		daNote.mesh.cameras = this.cameras;
		daNote.mesh.draw();
	}

	public function drawStuff(notePositions:Array<NotePositionData>) {
		for (noteData in notePositions) {
			if (noteData.isStrum) // draw strum
				drawStrum(noteData);
			else if (!notes.members[noteData.index].isSustainNote) // draw regular note
				drawNote(noteData);
			else { // draw sustain
				drawSustainNote(noteData);
			}
		}
	}

	public function getSustainPoint(noteData:NotePositionData, timeOffset:Float):NotePositionData {
		var daNote:Note = notes.members[noteData.index];
		var songSpeed:Float = notes.members[noteData.index].speed;
		var lane:Int = noteData.lane;
		var pf:Int = noteData.playfieldIndex;

		var noteDist:Float = getNoteDist(noteData.index);
		var curPos:Float = getNoteCurPos(noteData.index, timeOffset);

		curPos = modifierTable.applyCurPosMods(lane, curPos, pf);

		if ((daNote.wasGoodHit || (daNote.prevNote.wasGoodHit)) && curPos >= 0)
			curPos = 0;
		noteDist = modifierTable.applyNoteDistMods(noteDist, lane, pf);
		var incomingAngle:Array<Float> = modifierTable.applyIncomingAngleMods(lane, curPos, pf);
		if (noteDist < 0)
			incomingAngle[0] += 180; // make it match for both scrolls
		// get the general note path for the next note
		NoteMovement.setNotePath(daNote, lane, songSpeed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);
		// save the position data
		var noteData = createDataFromNote(noteData.index, pf, curPos, noteDist, incomingAngle);
		// add offsets to data with modifiers
		modifierTable.applyNoteMods(noteData, lane, curPos, pf);
		var yOffsetThingy = (NoteMovement.arrowSizes[lane] / 2);
		var finalNotePos = ModchartUtil.calculatePerspective(new Vector3D(noteData.x
			+ (daNote.width / 2)
			+ ModchartUtil.getNoteOffsetX(daNote, instance),
			noteData.y
			+ (NoteMovement.arrowSizes[noteData.lane] / 2), noteData.z * 0.001),
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(daNote.width / 2), yOffsetThingy
			- (NoteMovement.arrowSizes[noteData.lane] / 2));

		noteData.x = finalNotePos.x;
		noteData.y = finalNotePos.y;
		noteData.z = finalNotePos.z;

		return noteData;
	}

	public function getCorrectScrollSpeed() {
		if (inEditor)
			return PlayState.SONG.speed; // just use this while in editor so the instance shit works
		else
			return ModchartUtil.getScrollSpeed(playStateInstance);
		return 1.0;
	}

	public function createTween(Object:Dynamic, Values:Dynamic, Duration:Float, ?Options:TweenOptions):FlxTween {
		var tween:FlxTween = tweenManager.tween(Object, Values, Duration, Options);
		tween.manager = tweenManager;
		return tween;
	}

	public function createTweenNum(FromValue:Float, ToValue:Float, Duration:Float = 1, ?Options:TweenOptions, ?TweenFunction:Float->Void):FlxTween {
		var tween:FlxTween = tweenManager.num(FromValue, ToValue, Duration, Options, TweenFunction);
		tween.manager = tweenManager;
		return tween;
	}

	public function createBezierPathTween(Object:Dynamic, Values:Dynamic, Duration:Float, ?Options:TweenOptions):FlxTween {
		var tween:FlxTween = tweenManager.bezierPathTween(Object, Values, Duration, Options);
		tween.manager = tweenManager;
		return tween;
	}

	public function createBezierPathNumTween(Points:Array<Float>, Duration:Float, ?Options:TweenOptions, ?TweenFunction:Float->Void):FlxTween {
		var tween:FlxTween = tweenManager.bezierPathNumTween(Points, Duration, Options, TweenFunction);
		tween.manager = tweenManager;
		return tween;
	}

	override public function destroy() {
		if (modchart != null) {
			#if hscript
			for (customMod in modchart.customModifiers) {
				customMod.destroy(); // make sure the interps are dead
			}
			#end
		}
		super.destroy();
	}
}
