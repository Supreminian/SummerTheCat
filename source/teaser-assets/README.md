# 动态逗猫棒图层

teaser-rod.png：杆身，固定跟随鼠标。
teaser-feathers.png：羽毛，顶部挂环为旋转轴。
teaser-bell.png：铃铛，顶部挂环为旋转轴。

三张素材由内置 imagegen 从已确认的逗猫棒视觉稿拆分生成，透明通道保留。运行时由 TeaserCursor.swift 合成原生 NSCursor，TeaserMotion.swift 提供两个独立阻尼摆动状态。纹理只在构造时加载；状态未改变时不重复合成。

生成提示词核心约束：保留奶白/鼠尾草绿材质和光照；分别只保留杆身、竖直悬挂羽毛、竖直悬挂铃铛；删除其他物体；背景透明；无动作线和文字。

参考原稿：exec-e6ce3a06-84d9-49fe-a3cf-84b69f9b3904.png。
