extends Node
## 静态数值表：单位、警情、接警剧本、命名素材。
## 后期可迁移到 JSON/CSV 方便策划调参（见 docs/GDD.md §15）。

const MIN_PER_SEC := 0.5  # 1× 倍速下，每现实秒推进的游戏分钟

# ---------------------------------------------------------------- 成长
const LEVEL_BONUS := 0.08   # 每升一级，处置效率 +8%
const XP_PER_LEVEL := 60.0  # 升级所需经验 = XP_PER_LEVEL × 当前等级

# ---------------------------------------------------------------- 单位
const UNIT_TYPES := {
	"community": {
		"gi": "local_police", "name": "社区警务车", "short": "社区", "callsign": "社区",
		"facility": "station", "force": 1, "speed": 20.0,
		"cost": 60000, "upkeep": 1800, "staff": 1, "crew": "民警 1 · 辅警 1",
		"patrol": true, "patrol_radius": 190.0, "skill": "mediate",
		"body": Color(0.93, 0.94, 0.96), "stripe": Color(0.1, 0.3, 0.85),
		"desc": "派出所社区民警。唯一能调解纠纷、寻找走失人员、受理盗窃报案的警力；劫持案中担任谈判。",
	},
	"patrol": {
		"gi": "directions_car", "name": "巡逻警车", "short": "巡逻", "callsign": "巡逻",
		"facility": "patrol_hq", "force": 2, "speed": 25.0,
		"cost": 90000, "upkeep": 2600, "staff": 2, "crew": "民警 2",
		"patrol": true, "patrol_radius": 420.0, "skill": "control",
		"body": Color(0.93, 0.94, 0.96), "stripe": Color(0.1, 0.3, 0.85),
		"desc": "巡特警快反主力。负责醉酒滋事、打架斗殴、入室盗窃、抢劫等治安处突，并能追缉嫌疑人。",
	},
	"traffic": {
		"gi": "two_wheeler", "name": "交警铁骑", "short": "铁骑", "callsign": "铁骑",
		"facility": "traffic_hq", "force": 1, "speed": 31.0,
		"cost": 50000, "upkeep": 1400, "staff": 1, "crew": "民警 1",
		"patrol": true, "patrol_radius": 500.0, "moto": true, "skill": "traffic",
		"body": Color(0.95, 0.95, 0.95), "stripe": Color(0.08, 0.25, 0.7),
		"desc": "交警铁骑，全城最快。只有交警能勘查事故、疏导拥堵、查处醉驾。",
	},
	"swat": {
		"gi": "airport_shuttle", "name": "特警突击车", "short": "特警", "callsign": "特警",
		"facility": "swat_hq", "force": 4, "speed": 24.0,
		"cost": 260000, "upkeep": 6800, "staff": 4, "crew": "特警 4",
		"patrol": false, "patrol_radius": 0.0, "big": true, "skill": "assault",
		"body": Color(0.13, 0.15, 0.18), "stripe": Color(0.1, 0.3, 0.85),
		"desc": "特警突击组。持械伤人、劫持人质必须由特警突击处置，平时在支队待命。",
	},
}

const FACILITY_TYPES := {
	"station": {"gi": "local_police", "name": "派出所", "units": ["community"]},
	"patrol_hq": {"gi": "directions_car", "name": "巡特警大队", "units": ["patrol"]},
	"traffic_hq": {"gi": "traffic", "name": "交警中队", "units": ["traffic"]},
	"swat_hq": {"gi": "security", "name": "特警支队", "units": ["swat"]},
}

## 警种专长：每类警情需要特定专长的警力到场才能推进处置
const SKILLS := {
	"mediate": {"name": "调解", "gi": "forum", "unit": "community", "color": Color("3fd0ff")},
	"control": {"name": "处突", "gi": "shield", "unit": "patrol", "color": Color("5b8cff")},
	"traffic": {"name": "交管", "gi": "traffic", "unit": "traffic", "color": Color("2fe0a0")},
	"assault": {"name": "突击", "gi": "security", "unit": "swat", "color": Color("ff6a4a")},
}

# ---------------------------------------------------------------- 警情
## req: 处置所需专长 {专长: 数量}，缺任一专长时现场只能维持、无法推进
## match: 旧版匹配系数（保留作参考）
## force: 武力需求等级（单位 force ≥ 该值才能推进处置）
## need: 需求单位数量；dur: 基础处置时长（游戏分钟）
## esc: 超时未到场时升级为的警情；deadline: 升级 / 失败时限（游戏分钟）
const INCIDENTS := {
	"dispute": {"name": "邻里纠纷", "gi": "forum", "level": 1, "req": {"mediate": 1}, "force": 0, "need": 1, "dur": 14.0, "deadline": 40.0, "esc": "fight",
		"match": {"community": 1.6, "patrol": 1.0, "traffic": 0.6, "swat": 0.7}, "icon": "纠"},
	"missing": {"name": "走失老人", "gi": "person_search", "level": 1, "req": {"mediate": 1}, "force": 0, "need": 1, "dur": 24.0, "deadline": 60.0, "esc": "",
		"match": {"community": 1.6, "patrol": 1.1, "traffic": 0.9, "swat": 0.8}, "icon": "寻"},
	"theft": {"name": "盗窃（已离开）", "gi": "shopping_bag", "level": 1, "req": {"mediate": 1}, "force": 0, "need": 1, "dur": 16.0, "deadline": 50.0, "esc": "",
		"match": {"community": 1.3, "patrol": 1.2, "traffic": 0.6, "swat": 0.6}, "icon": "盗"},
	"ebike_theft": {"name": "电动车被盗", "gi": "two_wheeler", "level": 1, "req": {"mediate": 1}, "force": 0, "need": 1, "dur": 16.0, "deadline": 50.0, "esc": "",
		"match": {"community": 1.5, "patrol": 1.1, "traffic": 0.7, "swat": 0.5}, "icon": "电"},
	"lost_child": {"name": "儿童走失", "gi": "person_search", "level": 2, "req": {"mediate": 1, "control": 1}, "force": 0, "need": 2, "dur": 18.0, "deadline": 20.0, "esc": "",
		"match": {"community": 1.5, "patrol": 1.3, "traffic": 0.8, "swat": 0.6}, "icon": "童"},
	"crowd_dispute": {"name": "聚集纠纷", "gi": "groups", "level": 2, "req": {"mediate": 1, "control": 1}, "force": 1, "need": 2, "dur": 16.0, "deadline": 22.0, "esc": "fight",
		"match": {"community": 1.3, "patrol": 1.3, "traffic": 0.7, "swat": 0.8}, "icon": "聚"},
	"fraud_report": {"name": "电信诈骗报案", "gi": "phone_in_talk", "level": 2, "req": {"mediate": 1}, "force": 0, "need": 1, "dur": 24.0, "deadline": 45.0, "esc": "",
		"match": {"community": 1.5, "patrol": 1.0, "traffic": 0.5, "swat": 0.4}, "icon": "诈"},
	"traffic_minor": {"name": "交通事故（轻微）", "gi": "car_crash", "level": 1, "req": {"traffic": 1}, "force": 0, "need": 1, "dur": 14.0, "deadline": 30.0, "esc": "jam",
		"match": {"community": 0.7, "patrol": 0.8, "traffic": 1.8, "swat": 0.5}, "icon": "事"},
	"jam": {"name": "交通拥堵", "gi": "traffic", "level": 1, "req": {"traffic": 1}, "force": 0, "need": 1, "dur": 16.0, "deadline": 40.0, "esc": "",
		"match": {"community": 0.6, "patrol": 0.8, "traffic": 1.8, "swat": 0.4}, "icon": "堵"},
	"drunk": {"name": "醉酒滋事", "gi": "local_bar", "level": 2, "req": {"control": 1}, "force": 1, "need": 1, "dur": 12.0, "deadline": 24.0, "esc": "fight",
		"match": {"community": 1.1, "patrol": 1.4, "traffic": 0.8, "swat": 1.0}, "icon": "醉"},
	"fight": {"name": "打架斗殴", "gi": "sports_kabaddi", "level": 2, "req": {"control": 2}, "force": 2, "need": 2, "dur": 16.0, "deadline": 20.0, "esc": "armed",
		"match": {"community": 0.9, "patrol": 1.5, "traffic": 0.7, "swat": 1.3}, "icon": "斗"},
	"burglary": {"name": "入室盗窃（在场）", "gi": "door_open", "level": 2, "req": {"control": 1}, "force": 2, "need": 1, "dur": 16.0, "deadline": 18.0, "esc": "robbery",
		"match": {"community": 1.0, "patrol": 1.5, "traffic": 0.7, "swat": 1.2}, "icon": "窃"},
	"dui": {"name": "醉驾", "gi": "no_drinks", "level": 2, "req": {"traffic": 1}, "force": 1, "need": 1, "dur": 10.0, "deadline": 16.0, "esc": "traffic_major",
		"match": {"community": 0.6, "patrol": 1.1, "traffic": 1.8, "swat": 0.5}, "icon": "驾"},
	"robbery": {"name": "抢劫", "gi": "back_hand", "level": 3, "req": {"control": 1}, "force": 2, "need": 2, "dur": 20.0, "deadline": 16.0, "esc": "armed", "flee": true,
		"match": {"community": 0.8, "patrol": 1.5, "traffic": 0.9, "swat": 1.4}, "icon": "抢"},
	"traffic_major": {"name": "交通事故（伤亡）", "gi": "car_crash", "level": 3, "req": {"traffic": 1, "control": 1}, "force": 0, "need": 2, "dur": 28.0, "deadline": 16.0, "esc": "",
		"match": {"community": 0.7, "patrol": 0.9, "traffic": 1.8, "swat": 0.6}, "icon": "伤"},
	"armed": {"name": "持械伤人", "gi": "swords", "level": 3, "req": {"assault": 1, "control": 1}, "force": 3, "need": 2, "dur": 18.0, "deadline": 14.0, "esc": "hostage",
		"match": {"community": 0.7, "patrol": 1.2, "traffic": 0.6, "swat": 1.8}, "icon": "械"},
	"hostage": {"name": "劫持人质", "gi": "crisis_alert", "level": 4, "req": {"assault": 1, "control": 1, "mediate": 1}, "force": 4, "need": 2, "dur": 40.0, "deadline": 30.0, "esc": "",
		"match": {"community": 0.5, "patrol": 0.9, "traffic": 0.4, "swat": 2.0}, "icon": "质"},
	"prank": {"name": "恶作剧报警", "gi": "theater_comedy", "level": 1, "req": {}, "force": 0, "need": 1, "dur": 4.0, "deadline": 30.0, "esc": "",
		"match": {"community": 1.0, "patrol": 1.0, "traffic": 1.0, "swat": 1.0}, "icon": "?"},
}

## 各警情的分时段权重（按小时 0..23）
static func hour_weight(type_id: String, hour: int) -> float:
	var night := hour >= 20 or hour < 3
	var late := hour >= 1 and hour < 6
	var rush := (hour >= 7 and hour < 9) or (hour >= 17 and hour < 20)
	var day := hour >= 9 and hour < 18
	match type_id:
		"dispute": return 1.2 if (day or night) else 0.5
		"missing": return 1.0 if day else 0.25
		"theft": return 1.3 if day else 0.5
		"ebike_theft": return 1.1 if day else 0.35
		"lost_child": return 0.8 if day else 0.2
		"crowd_dispute": return 0.7 if (day or night) else 0.4
		"fraud_report": return 0.65 if day else 0.12
		"traffic_minor": return 1.8 if rush else 0.8
		"jam": return 1.6 if rush else 0.2
		"drunk": return 1.6 if night else 0.15
		"fight": return 1.2 if night else 0.3
		"burglary": return 1.1 if late else 0.3
		"dui": return 1.0 if night else 0.1
		"robbery": return 0.5 if (night or late) else 0.15
		"traffic_major": return 0.35 if rush else 0.2
		"armed": return 0.28 if night else 0.08
		"hostage": return 0.05
		"prank": return 0.25
	return 0.0

## 各小时的整体发案系数
static func hour_intensity(hour: int) -> float:
	var curve := [0.9, 0.75, 0.6, 0.45, 0.35, 0.35, 0.5, 0.85, 1.0, 0.9, 0.85, 0.9,
		0.95, 0.9, 0.85, 0.9, 1.0, 1.15, 1.15, 1.1, 1.2, 1.3, 1.25, 1.1]
	return curve[hour % 24]

# ---------------------------------------------------------------- 接警剧本
## true: 真实警情；report: 报警人描述导向的表面警情（系统默认按此研判）
## options: 玩家可选的定性；questions: {q, a}；{loc} {road} 会被替换
const CALLS := [
	{"true": "armed", "report": "fight", "caller": "男 · 约三十岁 · 情绪激动",
		"open": "喂？110吗？这边……这边打起来了！好几个人！",
		"questions": [
			{"q": "对方手里有没有拿东西？", "a": "有！有个人拿着刀！刚刚还挥了一下！"},
			{"q": "有没有人受伤？", "a": "地上躺着一个……好像在流血，我不敢过去……"},
			{"q": "现在具体在什么位置？", "a": "就在{loc}，旁边有个烧烤摊。"},
			{"q": "您先找个安全的地方，别挂电话。", "a": "好、好……我躲到车后面了。"},
		],
		"options": ["fight", "armed", "drunk"]},
	{"true": "robbery", "report": "theft", "caller": "女 · 约五十岁 · 惊慌",
		"open": "我的包！我的包被人抢了！就刚才！",
		"questions": [
			{"q": "对方有没有对您动手？", "a": "他推了我一把，手里还拿着个东西吓唬我……"},
			{"q": "嫌疑人往哪个方向跑了？", "a": "骑电动车往{road}那边跑了，穿黑衣服，戴头盔！"},
			{"q": "您有没有受伤？", "a": "手擦破了点……没事，你们快来！"},
			{"q": "包里有什么贵重物品？", "a": "手机、钱包，还有我的身份证……"},
		],
		"options": ["theft", "robbery", "dispute"]},
	{"true": "hostage", "report": "armed", "caller": "男 · 声音压低 · 极度紧张",
		"open": "救……救命……有个人拿刀……在店里……",
		"questions": [
			{"q": "他现在在做什么？", "a": "他……他抓着收银员……刀抵着脖子……在喊要钱……"},
			{"q": "店里还有多少人？", "a": "我和另外两个顾客躲在货架后面……"},
			{"q": "是什么店？在哪？", "a": "{loc}的便利店，24小时那家……"},
			{"q": "保持安静，别让他发现您。", "a": "（急促的呼吸声）……嗯……"},
		],
		"options": ["armed", "hostage", "robbery"]},
	{"true": "traffic_major", "report": "traffic_minor", "caller": "男 · 约四十岁 · 司机",
		"open": "撞车了，两辆车撞一块了，在{loc}。",
		"questions": [
			{"q": "有没有人受伤？", "a": "有个骑电动车的……倒在地上不动了……"},
			{"q": "车辆还能移动吗？", "a": "一辆车头全瘪了，漏油了……"},
			{"q": "现场有没有起火？", "a": "没有火，但是有烟……"},
			{"q": "请打开双闪，人员撤到护栏外。", "a": "好的，我已经下车了。"},
		],
		"options": ["traffic_minor", "traffic_major", "jam"]},
	{"true": "prank", "report": "robbery", "caller": "童声 · 约十岁",
		"open": "喂喂！有人抢银行！好多好多坏人！",
		"questions": [
			{"q": "小朋友，你家大人在旁边吗？", "a": "……（笑声）……妈妈在做饭……"},
			{"q": "银行在哪里？", "a": "就在……就在月亮上！哈哈哈哈！"},
			{"q": "你看到坏人拿着什么？", "a": "拿着……拿着奥特曼！嘿嘿……"},
			{"q": "报警电话不能乱打，知道吗？", "a": "……（嘟——嘟——）"},
		],
		"options": ["robbery", "prank", "hostage"]},
	{"true": "drunk", "report": "fight", "caller": "女 · 约六十岁 · 住户",
		"open": "楼下有人在闹，砸东西，嗓门特别大，吓死人了！",
		"questions": [
			{"q": "他们在打人吗？", "a": "没有打人，就一个人，喝多了在砸啤酒瓶。"},
			{"q": "对方拿着什么东西？", "a": "就……就酒瓶子，砸了一地了。"},
			{"q": "具体在哪栋楼下？", "a": "{loc}，小区门口那个小卖部边上。"},
			{"q": "您先别下楼，关好门窗。", "a": "哎，好，我在阳台上看着呢。"},
		],
		"options": ["fight", "drunk", "dispute"]},
	{"true": "burglary", "report": "dispute", "caller": "女 · 约三十岁 · 小声",
		"open": "我……我邻居家好像有动静，可是他们全家出国了啊……",
		"questions": [
			{"q": "您能听到什么声音？", "a": "像是撬门的声音，还有手电筒在晃……"},
			{"q": "有几个人？", "a": "看影子……至少两个。"},
			{"q": "您家的门锁好了吗？", "a": "锁好了，我不敢出声……"},
			{"q": "具体地址是哪里？", "a": "{loc}，六楼，602。"},
		],
		"options": ["dispute", "burglary", "theft"]},
	{"true": "fight", "report": "fight", "caller": "男 · 约二十岁 · 夜市摊主",
		"open": "打架了打架了！两伙人在夜市打起来了！",
		"questions": [
			{"q": "有人拿东西吗？", "a": "没看到拿家伙，就是拳头，还有人扔凳子！"},
			{"q": "大概多少人？", "a": "七八个吧，都喝了酒。"},
			{"q": "有人受伤吗？", "a": "有个流鼻血了，不严重。"},
			{"q": "具体在哪？", "a": "{loc}的夜市，靠路口那头。"},
		],
		"options": ["fight", "armed", "drunk"]},
	{"true": "armed", "report": "armed", "caller": "男 · 约四十岁 · 保安",
		"open": "我是这边的保安！有人拿着钢管在追砍人！",
		"questions": [
			{"q": "持械的有几个人？", "a": "一个，就一个！疯了一样！"},
			{"q": "现在有伤者吗？", "a": "有个小伙子胳膊挨了一下，跑进楼里了。"},
			{"q": "您能疏散周围群众吗？", "a": "我在喊了，人都在往外跑……"},
			{"q": "位置在哪？", "a": "{loc}，写字楼大堂门口！"},
		],
		"options": ["fight", "armed", "hostage"]},
	{"true": "robbery", "report": "robbery", "caller": "男 · 约二十五岁 · 外卖骑手",
		"open": "110！我刚看见有人在抢一个姑娘的手机！",
		"questions": [
			{"q": "嫌疑人有凶器吗？", "a": "好像没有，就是一把拽走了，人往巷子里跑了。"},
			{"q": "被害人现在怎么样？", "a": "坐地上哭，我在陪着她。"},
			{"q": "嫌疑人什么特征？", "a": "瘦高个，灰色卫衣，往{road}方向跑的！"},
			{"q": "谢谢您，请留在原地等民警。", "a": "好嘞，我等着。"},
		],
		"options": ["theft", "robbery", "dispute"]},
	{"true": "lost_child", "report": "lost_child", "caller": "女 · 约三十岁 · 着急",
		"open": "我女儿不见了！刚才还在公园门口的！求你们快找找！",
		"questions": [
			{"q": "小朋友多大？穿什么衣服？", "a": "五岁，穿红色的衣服，头发短短的，个子小小的。"},
			{"q": "最后一次看到是在哪里？", "a": "就在{loc}的滑梯旁边，我就低头看了下手机……"},
			{"q": "名字是什么？", "a": "小名多多……你们快点好不好！"},
			{"q": "您先在原地等，我们马上派警力。", "a": "好好，我就在门口，求你们了……"},
		],
		"options": ["lost_child", "missing", "prank"]},
	{"true": "fraud_report", "report": "fraud_report", "caller": "女 · 约四十岁 · 焦急",
		"open": "我上当了！钱转出去了，对方现在找不到人了！",
		"questions": [
			{"q": "对方是怎么找到您的？", "a": "先来电话，自称是客服，我收到的东西有质量问题要退款……"},
			{"q": "您是怎么转账的？", "a": "他让我点开一个网页，走什么刷单返利的流程，我就转了两次……"},
			{"q": "一共转了多少？", "a": "卡里的钱都转了，是在{road}这边的银行转的……"},
			{"q": "请先别再转账，带好手机来所里做记录。", "a": "好好，我现在就过去，钱还能追回来吗……"},
		],
		"options": ["fraud_report", "prank", "theft"]},
]

# ---------------------------------------------------------------- 命名素材
const ROAD_NAMES_H := ["北郊路", "环城北路", "北环路", "新华路", "解放路", "人民路", "中山路", "建设路", "和平路",
	"滨江路", "江南路", "长江路", "胜利路", "学府路", "南环路", "迎宾路", "环城南路", "南郊路"]
const ROAD_NAMES_V := ["西郊街", "环城西路", "西山街", "文化街", "青年街", "东风大道", "五一街", "府前街", "朝阳街",
	"光明街", "花园街", "工农街", "东湖街", "新城大道", "望江街", "环城东路", "东郊街", "春风街"]

const SURNAMES := ["王", "李", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴", "徐", "孙", "胡", "朱", "高", "林", "何", "郭", "马", "罗", "梁", "宋", "郑", "谢", "韩", "唐", "冯", "于", "董", "萧"]
const GIVEN := ["建国", "志强", "海涛", "晓东", "立新", "伟", "磊", "军", "勇", "静", "丽华", "红梅", "晨", "浩然", "子轩", "思远", "一鸣", "文博", "明杰", "雪", "佳怡", "国栋", "振华", "少龙", "天宇", "家豪", "卫东", "春生", "晓峰", "敏"]
const RANKS := ["二级警员", "一级警员", "三级警司", "二级警司", "一级警司", "三级警督"]

static func random_name(rng: RandomNumberGenerator) -> String:
	return SURNAMES[rng.randi() % SURNAMES.size()] + GIVEN[rng.randi() % GIVEN.size()]

static func money_str(v: float) -> String:
	var neg := v < 0
	var s := str(int(abs(v)))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if neg else "") + "¥" + out

## 专长需求的文字描述，如 "处突×2 · 交管"
static func req_text(req: Dictionary) -> String:
	if req.is_empty():
		return "任意警力"
	var parts := []
	for k in req.keys():
		var n := int(req[k])
		parts.append(SKILLS[k].name + ("×%d" % n if n > 1 else ""))
	return " · ".join(parts)


static func req_count(req: Dictionary) -> int:
	var n := 0
	for k in req.keys():
		n += int(req[k])
	return maxi(n, 1)


static func level_color(level: int) -> Color:
	match level:
		1: return Color("f0a020")
		2: return Color("ff7a1a")
		3: return Color("ff3d4a")
		_: return Color("e0287a")

static func level_name(level: int) -> String:
	return ["", "一般", "较大", "重大", "特别重大"][clampi(level, 0, 4)]
