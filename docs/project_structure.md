# โครงสร้างโปรเจค

## โฟลเดอร์หลัก

| โฟลเดอร์ | ใช้เก็บ |
| --- | --- |
| `assets/models/characters/` | โมเดลนักโทษและตำรวจ |
| `assets/models/environment/` | โมเดลครัวและ texture ที่มากับโมเดล |
| `assets/models/props/` | โมเดลอาหาร อุปกรณ์ ตู้เย็น ประตู และ texture ที่มากับโมเดล |
| `assets/audio/music/` | เพลงประกอบ |
| `assets/audio/sfx/` | เสียงการกระทำ เช่น สับอาหาร ทอด เปิดประตู โดนตี |
| `assets/audio/ambience/` | เสียงบรรยากาศวนซ้ำ |
| `assets/audio/voice/` | เสียงพูดและเสียงตัวละคร |
| `assets/textures/ui/` | ภาพ UI; ภาพคู่มืออยู่ใน `tutorial/` |
| `assets/textures/particles/` | ภาพควัน ประกาย ไอน้ำ หรือ sprite sheet สำหรับพาร์ติเคิล |
| `scenes/characters/` | ซีนผู้เล่น นักโทษ ragdoll และถาดที่นักโทษถือ |
| `scenes/items/` | ของที่หยิบได้ แยก `foods/`, `cookware/`, `tools/` |
| `scenes/props/stations/` | เตา ตู้เย็น โต๊ะเสิร์ฟ ถังขยะ |
| `scenes/props/food_sources/` | จุดหยิบวัตถุดิบแบบไม่จำกัด |
| `scenes/props/interactive/` | ประตู ปุ่มเปิด–ปิดครัว และป้ายคู่มือ |
| `scenes/ui/` | เมนูหลัก Pause สรุปวัน Game Over และ Tutorial |
| `scenes/world/` | ซีนฉากแวดล้อมที่นำกลับมาใช้ได้ |
| `scenes/effects/particles/` | ซีนเอฟเฟค เช่น `cooking_steam.tscn` ที่มี GPUParticles3D |
| `scripts/` | โค้ด แบ่งหมวดตรงกับหน้าที่ของซีน |
| `scripts/managers/` | Autoload: GameManager, QueueManager |
| `scripts/queue/` | การเชื่อมระบบคิวกับฉาก และ spawner |
| `scripts/resources/` | คลาสข้อมูล wave และ progression ที่ปรับผ่าน Inspector |
| `scripts/components/` | ส่วนที่ใช้ซ้ำ เช่น ตัวควบคุมอนิเมชั่นบานเปิด |
| `scripts/effects/` | โค้ดควบคุมเอฟเฟคที่จะเพิ่มภายหลัง |
| `resources/meshes/` | Mesh `.tres` ที่แยกมาจาก GLB ด้วย Advanced Import |
| `resources/materials/` | Material ที่ใช้ร่วมกัน |
| `resources/collision/` | Shape collision ที่แยกเป็นไฟล์ |
| `resources/navigation/` | Navigation mesh ของครัว |
| `resources/themes/` | Theme ของ UI |
| `resources/particles/` | ParticleProcessMaterial, Curve และ Gradient ที่ใช้ร่วมกัน |
| `shaders/` | Shader เช่น เอฟเฟคจอเบลอ |
| `tests/` | สคริปต์ทดสอบระบบ |
| `docs/testing/` | คำอธิบายระบบและวิธีทดสอบ |
| `docs/archive/` | ข้อมูลอ้างอิงเก่าที่ไม่ถูกโหลดเป็นซีนในเกม |

โฟลเดอร์ที่ยังว่างมี `.gitkeep` เพื่อให้ Git เก็บโครงสร้างไว้ โดยยังไม่ได้เพิ่มระบบเล่นเสียงหรือเอฟเฟคจริง

Texture ที่ Godot แยกจากโมเดลถูกเก็บข้าง GLB เพื่อให้ reimport ได้ตามเดิม ส่วนภาพที่สร้างเพิ่มเองให้ใส่ `assets/textures/` การตั้งค่า Save to File ของ GLB ชี้ไป `resources/meshes/` แล้ว

ใช้ชื่อไฟล์ซีนและสคริปต์แบบ `snake_case` ส่วนชื่อไฟล์โมเดลจากโปรแกรม 3D คงชื่อเดิมไว้เพื่อจับคู่กับต้นฉบับได้ง่าย ย้ายไฟล์ครั้งต่อไปผ่าน FileSystem dock ของ Godot เพื่ออัปเดตจุดอ้างอิงพร้อมกัน และเก็บ `.uid` / `.import` ไปกับไฟล์ต้นทาง

## Node ใน main.tscn

```text
Main
├── Environment         โมเดลครัว แสง WorldEnvironment และ KitchenNavigation
├── Actors
│   └── Player
├── Kitchen
│   ├── Stations        ServingTable, Stove, Stove2, Fridge
│   ├── FoodSources     จุดหยิบวัตถุดิบทั้งห้า
│   └── Interactables   TrashCan, PrisonerDoor, CloseKitchenButton, TutorialSign
├── Items               Knife, Pan, Pot, Tray, Tray2
├── Queue
│   └── QueueLayout     จุดรอ จุดรับถาด จุดเสิร์ฟ ทางออก Spawner และ Prisoners
└── UI                  ServiceHUD, DaySummary, PauseMenu, TutorialPopup
```

Node ที่เพิ่มเพื่อจัดหมวดมี transform เริ่มต้น จึงไม่เปลี่ยนตำแหน่ง ขนาด หรือการหมุนของของเดิม ค่าผู้เล่น อุปกรณ์ โมเดล และจำนวนคิวคงตามฉากก่อนจัดระเบียบ จุดหยิบวัตถุดิบยังอยู่ในตำแหน่งที่ปรับไว้ล่าสุด

เลือก `Queue/QueueLayout` เพื่อกำหนดวันแรกและความยาก; `serving_table_path` กับ `player_path` เชื่อมไปยังกลุ่มใหม่แล้ว UI ยังเป็นซีนจริงที่แก้ใน editor ได้

เมื่อย้ายสิ่งกีดขวาง ให้สร้าง navigation ใหม่ด้วย:

```powershell
godot --headless --path <project> --script res://scripts/tools/bake_kitchen_navigation.gd
```

การจัดกลุ่มครั้งนี้ไม่เปลี่ยนตำแหน่งสิ่งกีดขวาง จึงเก็บ navigation mesh เดิมไว้
