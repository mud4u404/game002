class_name MapData
extends RefCounted
## 辖区地图设计数据："江城市 · 滨江分局辖区"（约 840 × 600 米）
## 坐标：x 向东，z 向南，单位米。道路为折线中心线，自动求交成路网。

## 辖区（可游玩）范围与世界范围
const PLAY := Rect2(-420, -300, 840, 600)
const WORLD := Rect2(-560, -420, 1120, 840)

## 道路等级：宽度（含两侧车行道）、中心线类型、车道数
const CLASSES := {
	"A": {"w": 24.0, "center": "double_yellow", "lanes": 3},  # 主干道
	"B": {"w": 17.0, "center": "yellow", "lanes": 2},         # 次干道
	"C": {"w": 11.0, "center": "dash", "lanes": 1},           # 支路
	"D": {"w": 6.5, "center": "none", "lanes": 1},            # 老城巷道
}

const ROADS := [
	{"name": "人民路", "cls": "A", "pts": [Vector2(-600, -52), Vector2(-240, -58), Vector2(40, -48), Vector2(280, -36), Vector2(600, -28)]},
	{"name": "滨江路", "cls": "A", "pts": [Vector2(-600, 142), Vector2(-420, 152), Vector2(-262, 166), Vector2(-100, 172), Vector2(60, 160), Vector2(220, 168), Vector2(380, 184), Vector2(600, 200)]},
	{"name": "中山大道", "cls": "A", "pts": [Vector2(38, -460), Vector2(38, -206), Vector2(40, -48), Vector2(52, 60), Vector2(60, 160), Vector2(64, 300), Vector2(68, 460)]},
	{"name": "解放路", "cls": "B", "pts": [Vector2(-600, -214), Vector2(-240, -214), Vector2(38, -206), Vector2(280, -200), Vector2(600, -194)]},
	{"name": "府前街", "cls": "B", "pts": [Vector2(-240, -460), Vector2(-240, -214), Vector2(-240, -58), Vector2(-252, 60), Vector2(-262, 166)]},
	{"name": "东风街", "cls": "B", "pts": [Vector2(280, -460), Vector2(280, -200), Vector2(280, -36), Vector2(292, 62), Vector2(300, 176)]},
	{"name": "和平路", "cls": "B", "pts": [Vector2(40, -48), Vector2(160, -122), Vector2(280, -200)]},
	{"name": "江南路", "cls": "B", "pts": [Vector2(-600, 330), Vector2(-200, 322), Vector2(64, 316), Vector2(600, 334)]},
	{"name": "文化街", "cls": "C", "pts": [Vector2(-404, -460), Vector2(-404, -214), Vector2(-404, -55), Vector2(-412, 60), Vector2(-418, 151)]},
	{"name": "学府路", "cls": "C", "pts": [Vector2(-600, -132), Vector2(-404, -134), Vector2(-240, -136)]},
	{"name": "学府路", "cls": "C", "pts": [Vector2(280, -118), Vector2(420, -116), Vector2(600, -112)]},
	{"name": "青年街", "cls": "C", "pts": [Vector2(160, -460), Vector2(160, -330), Vector2(160, -203)]},
	{"name": "青年街", "cls": "C", "pts": [Vector2(163, -42), Vector2(170, 60), Vector2(176, 164)]},
	{"name": "光明街", "cls": "C", "pts": [Vector2(-112, -210), Vector2(-110, -56)]},
	{"name": "新华路", "cls": "C", "pts": [Vector2(-600, -330), Vector2(-240, -330), Vector2(38, -330), Vector2(280, -330), Vector2(600, -330)]},
	{"name": "建设路", "cls": "C", "pts": [Vector2(-600, 56), Vector2(-412, 60), Vector2(-252, 60), Vector2(-110, 62), Vector2(52, 60)]},
	{"name": "建设路", "cls": "C", "pts": [Vector2(52, 60), Vector2(170, 60), Vector2(292, 62), Vector2(430, 64), Vector2(600, 68)]},
	{"name": "东湖街", "cls": "C", "pts": [Vector2(430, -460), Vector2(430, -200), Vector2(428, -32), Vector2(430, 64), Vector2(436, 188)]},
	# 老城巷道
	{"name": "槐树巷", "cls": "D", "pts": [Vector2(-178, -56), Vector2(-176, 0), Vector2(-174, 61), Vector2(-170, 168)]},
	{"name": "井巷", "cls": "D", "pts": [Vector2(-110, -56), Vector2(-112, 4), Vector2(-110, 62)]},
	{"name": "井巷", "cls": "D", "pts": [Vector2(-110, 62), Vector2(-106, 118), Vector2(-102, 171)]},
	{"name": "鼓楼巷", "cls": "D", "pts": [Vector2(-48, -52), Vector2(-50, 8), Vector2(-46, 61), Vector2(-40, 168)]},
	{"name": "书院巷", "cls": "D", "pts": [Vector2(-246, 4), Vector2(-178, 2), Vector2(-112, 4), Vector2(-50, 8), Vector2(46, 6)]},
	{"name": "米市巷", "cls": "D", "pts": [Vector2(-257, 112), Vector2(-172, 114), Vector2(-106, 118), Vector2(-42, 114), Vector2(56, 110)]},
]

## 江：中心线与宽度
const RIVER := [Vector2(-640, 222), Vector2(-420, 230), Vector2(-200, 240), Vector2(-20, 246), Vector2(160, 238), Vector2(340, 250), Vector2(640, 268)]
const RIVER_W := 74.0

## 分区（按街区中心点落在哪个区域判断；越靠前优先级越高）
const ZONES := [
	{"zone": "riverside", "rect": Rect2(-640, 150, 1280, 70), "below_road": "滨江路"},
	{"zone": "oldtown", "rect": Rect2(-252, -52, 300, 222)},
	{"zone": "cbd", "rect": Rect2(-112, -206, 280, 160)},
	{"zone": "park", "rect": Rect2(170, 62, 130, 110)},
	{"zone": "school", "rect": Rect2(-404, -214, 164, 80)},
	{"zone": "commercial", "rect": Rect2(-240, -214, 128, 160)},
	{"zone": "commercial", "rect": Rect2(-404, -134, 164, 80)},
	{"zone": "residential", "rect": Rect2(-640, -460, 1280, 920)},
]

## 公安设施：放在包含该点的街区内
const FACILITIES := [
	{"type": "station", "name": "滨江派出所", "at": Vector2(-10, -90)},
	{"type": "station", "name": "老城派出所", "at": Vector2(-210, 88)},
	{"type": "patrol_hq", "name": "巡特警大队", "at": Vector2(222, -70)},
	{"type": "traffic_hq", "name": "交警二中队", "at": Vector2(-330, -95)},
	{"type": "swat_hq", "name": "特警支队", "at": Vector2(360, 120)},
]
