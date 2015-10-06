---
title:
layout: post
tags: unity
categories: unity

---

### 动画系统

如果动画包含多层，要设置动画层权重

通常情况下，在我们操作角色时，脚本根据玩家输入，设置动画的行进速度(可平滑过度)，由动画的Blend Tree来做到角色走和跑之间的平滑过渡，并且将动画的实际位移作用于角色模型上。也就是说，由动画控制前进(走，跑)，脚本直接控制转向(`rigidbody.MoveRotation`)。模型只需提供`Walk`和`Run`两个动画片段即可，但需要导入位移信息。

Animator有个比较有用的选项，用于通过脚本而不是动画来控制模型移动。

`Apply Root Motion`：是否将动画的位移，转向作用于实际模型之上。即模型的运动(Position，Rotation的变化)是由动画控制还是脚本控制。

Apply Root Motion的作用示例：

![](asset/image/unity/apply_root_motion_demo.gif)

当取消`Apply Root Motion`时，动画的转向和移动都将被屏蔽，只显示动画本身的动作。`Apply Root Motion`在一些场合下很有用，比如当模型自己有AI：

NavMeshAgent: 寻路组件，要使用它，首先要烘培寻路地形(Windows->Navigation)，然后设置目标位置。NavMeshAgent组件会自动将游戏对象按照当前最佳路径移动至目标位置。默认情况下，Nav会自动控制模型的移动和转向。可通过`nav.updateRotation/updatePosition`决定NavMeshAgent对游戏对象的控制权，当两者都为False时，角色当原地不动。

在游戏中，敌人或者是小兵通常同时具有Animator和NavMeshAgent，而如果此时我们想实现一些比较灵活的控制：比如敌人在寻路至目标点附近(比如刚好看到目标)时，停止移动(进行远程射击)。

此时有两种做法：

1. 由NavMeshAgent控制敌人移动

	此时禁用`Apply Root Motion`，Animator只做表现。在游戏逻辑中，根据当前Nav期望速度(决定前进速度和转向速度分量)，与目标的视角(当视角小于一定角度时，直接`LookAt`到目标位置方向，避免缓冲时间太慢)，是否已经看到目标(此时停下来，看向目标，开枪)等条件，设置Animator的`speed`(前进速度)和`angularSpeed`(转向速度)，此时动画层会作出响应的动作，如走，跑，转向等，但是没有实际运动(位移和转向)。然后在`OnAnimatorMove`中：
	
		void OnAnimatorMove()
	    {
	        nav.velocity = anim.deltaPosition / Time.deltaTime;
	    }
	    
	这样我们可以使得动画层和表现和实际运动基本一致，每帧`Update()`在`OnAnimatorMove()`之前调用，所有状态都记录到了Animator中。由于Nav的转向是比较生硬的，我们也可以让动画来控制转向：首先在`Awake()`中`nav.updateRotation = false;`不让Nav调整敌人转向，然后在`OnAnimatorMove()`中添加：`transform.rotation = anim.rootRotation;`。

2. 由动画控制敌人移动

	逻辑处理不变，取消`OnAmimatorMove()`，勾选`Apply Root Motion`，并且同时禁用NavMeshAgent的updateRotation和updatePosition。
	
	Unity官方Stealth教程使用的是前一种方法，但个人觉得后一种方法更好，在确保动画层表现和角色运动状态一致的情况下，利用`nav.desiredVelocity`得出当前运动矢量(speed, angularSpeed)，并设置到动画。