//广告页面

import 'dart:async';
import 'dart:convert' as convert;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:vrapp/common/color.dart';
import 'package:vrapp/utils/account_util.dart';

import '../common/navigator_util.dart';
import '../r.dart';
import '../utils/jumper_utils.dart';
import '../utils/launch_utils.dart';
import '../utils/sandbox_info_util.dart';
import '../utils/umeng_util.dart';
import 'main_page.dart';

//广告图媒体类型
enum AdverMediaType{

  AdverMediaType_image,//图片类型
  AdverMediaType_video,//视频类型
}

class AdvertisingPage extends StatefulWidget {
  final String adverInfo;//广告页面信息
  AdvertisingPage(
    {
      Key? key,
      required this.adverInfo,

    }) : super(key: key);

  @override
  State<AdvertisingPage> createState() => _AdvertisingPageState();
}

class _AdvertisingPageState extends State<AdvertisingPage> {

  Timer? _timer;
  int _timeCount = 5;//单位秒
  late String _advURL = "";//广告图
  late Map _advJumpMap = Map();//广告跳转信息
  late AdverMediaType _mediaType = AdverMediaType.AdverMediaType_image; //广告图媒体类型
  late VideoPlayerController _controller;//视频播放器controller
  late bool _initialized = false;//视频controller已经初始化了


  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    //配置广告信息
    configAdvInfo();

    //如果信息不对，直接进入首页
    if(!checkInfo()){
      return;
    }

    //界面build完成后执行回调函数
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(!mounted)return;
      //开启定时器
      startTimer();
    });
  }
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [

        //广告图
        advView,

        //跳过广告view
        skipView,

        //上滑或者点击，查看更多
        _showMoreView,

      ],
    );
  }

  //广告图
  Widget get advView{

    Widget view;

    view = _mediaType == AdverMediaType.AdverMediaType_image ? 
    Image.network(_advURL,
      width: 1.sw,
      height: 1.sh,
      fit: BoxFit.cover,
    )
      // ImageUtils(_advURL,
      //   width: 1.sw,
      //   height: 1.sh,
      //   showErrorImage: false,
      //   showPlaceholderImage: false,
      //   fit: BoxFit.cover,
      // )
      .gestures(

        onTap: (){
          
          //埋点
          bool isShow = !SandBoxInfoUtil.getInstace()!.agreedProtocol;
          if(isShow){
            UmengUtil.event('advertisingPageClick');
          }
          //进入广告设置跳转页面
          jumpAdvConfigPage();    
        },

        onVerticalDragEnd:(DragEndDetails onVerticalDragEnd){//垂直拖动-结束

          DragEndDetails details = onVerticalDragEnd;
          double currectDy =  details.velocity.pixelsPerSecond.dy;
          if(currectDy < 0){//向上拖动
            //进入广告设置跳转页面
            jumpAdvConfigPage();    
          }
        }
      )
      : videoPlayView.gestures(

          onTap: (){
      
            //进入广告设置跳转页面
            jumpAdvConfigPage();    
          },

          onVerticalDragEnd:(DragEndDetails onVerticalDragEnd){//垂直拖动-结束

            DragEndDetails details = onVerticalDragEnd;
            double currectDy =  details.velocity.pixelsPerSecond.dy;
            if(currectDy < 0){//向上拖动
              //进入广告设置跳转页面
              jumpAdvConfigPage();    
            }
          }
        );
    
    return view;
  }

  //跳过广告view
  Widget get skipView{

    return Container(
      alignment: Alignment.topRight,
      decoration: BoxDecoration(
        color: ProjectColor.colorBlack00.withOpacity(0.4),
        borderRadius: BorderRadius.all(Radius.circular(29.w)),
      ),
      child: Text('跳过 $_timeCount')
        .textColor(ProjectColor.colorWhite)
        .fontSize(26.sp)
        .textAlignment(TextAlign.center)
        .alignment(Alignment.center),
    ).width(120.w)
    .height(58.w)
    .padding(top: 90.w,right: 32.w)
    .alignment(Alignment.topRight)
    .gestures(onTap: (){

      //取消定时器
      _cancelTimer();
      //进入首页
      jumpHomePage();
    });
  }

  //上滑或者点击，查看更多
  Widget get _showMoreView{

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
           decoration: BoxDecoration(
            color: Color(0xFF1D1D1D).withOpacity(0.6),
            borderRadius: BorderRadius.all(Radius.circular(60.w)),
          ),
          child: Text('上滑或点击，查看更多内容')
          .textColor(ProjectColor.colorWhite)
          .fontSize(32.sp)
          .textAlignment(TextAlign.center)
          .alignment(Alignment.center),
        )
        .width(550.w)
        .height(120.w),

        //ico
        Image.asset(
          R.imagesIcPutupArrow,
          width: 52.w,
          height: 62.w,
        ).padding(top: 24.w),
      ],
    ).padding(left: 10.w,right: 10.w,bottom: 80.w)
    .alignment(Alignment.center)
    .gestures(onTap: (){
      
     //进入广告设置跳转页面
     jumpAdvConfigPage();
      
    });
  }

  //视频播放器
  Widget get videoPlayView{

    if(!_initialized){

      _controller = VideoPlayerController.network(_advURL)
      ..initialize().then((_) {
        
        // _controller.setVolume(0);//静音
        _controller.play();
      }).catchError((e) {
        //播放失败，进入首页
        jumpHomePage();
      });
    }
   _initialized = true;

   return VideoPlayer(_controller,)
      .width(1.sw)
      .height(1.sh);
  }

  //进入首页
  Future<void> jumpHomePage(
    {
      bool showTransitions = false,//显示转场动画
    }
  ) async {
    //修改是否第一次安装记录
    SharedPreferences pref = await SharedPreferences.getInstance();
    pref.setBool('isFirstInstall', false);
    //进入首页
    //  Navigator.of(context).pushAndRemoveUntil(
    //   CustomTransitionRoute().customRoute((context) => new MainWidget(),type: CustomTransitionRouteType.fade,route: "/"),
    //   // ignore: unnecessary_null_comparison
    //   (route) => route == null
    // );
    NavigatorUtil.pushRePlace((context) => new MainWidget(), route: "/");
  }

  //进入广告设置跳转页面
  void jumpAdvConfigPage(){

    //取消定时器
    _cancelTimer();
    //进入首页
    jumpHomePage(showTransitions: true);
    //进入指定页面
    Future.delayed(Duration(milliseconds: 350), () {
      int type = _advJumpMap['type'];
      String ext = _advJumpMap['ext'];
      JumperUtils.firstJumpPage(type, ext);

      if((type == 17 || type == 20 ||type == 22 || type == 23 || type == 25) && !AccountUtil.isLogin){
        //如果有需要登录的页面、记录需要登录的页面信息，登录成功后，跳转
        LaunchUtil.advNeedJumpPageInfo = convert.jsonEncode(_advJumpMap);
      }

    });
  }


   //配置广告信息
  void configAdvInfo(){
  
    if(widget.adverInfo.isNotEmpty){

      Map<String ,dynamic> advMap = convert.jsonDecode(widget.adverInfo);
      //广告图
      _advURL = advMap['url']??"";

      //广告跳转信息
      if(advMap['jumpInfo'] != null){
        _advJumpMap = convert.jsonDecode(advMap['jumpInfo']);
      }

      //广告时长
      _timeCount = (advMap['advTime'] is int) ? advMap['advTime'] : 5;

      //媒体类型
      _mediaType = advMap['mediaType'] == 2 ? AdverMediaType.AdverMediaType_video : AdverMediaType.AdverMediaType_image;

    }
  }
  //如果信息不对，直接进入首页
  bool checkInfo(){
    // ignore: unrelated_type_equality_checks, unnecessary_type_check
    if(_advURL.isEmpty || !(_advJumpMap is Map) || _advJumpMap.isEmpty){
      //进入首页
      jumpHomePage();
      return false;
    }
    return true;
  }


  ///计时器
  void startTimer() {
    Timer.periodic(Duration(seconds: 1), (Timer timer) {
      _timer = timer;
      if(!mounted) return;
      setState(() {
        
        if (_timeCount <= 1) {

         //进入首页
         jumpHomePage();

          timer.cancel();
         _timeCount = 0;

        } else {
          _timeCount -= 1;
        }

      });
    });
  }

  //停止定时器
  // ignore: unused_element
  _cancelTimer() {
    if(_timer != null && _timer!.isActive){
       _timer?.cancel();
       _timeCount = 5;
    }
  }
}