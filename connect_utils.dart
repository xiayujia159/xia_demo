//UDP&TCP连接管理类
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:vrapp/common/base_api.dart';
import 'package:vrapp/common/constants.dart';
import 'package:vrapp/entity/v_r_i_p_info_entity.dart';
import 'package:vrapp/pages/log/custom_log.dart';
import 'package:vrapp/utils/account_util.dart';
import 'package:vrapp/utils/aes_utils.dart';
import 'package:vrapp/utils/event_bus.dart';
import 'package:vrapp/utils/http_utils.dart';
import 'package:vrapp/utils/json_utils.dart';
import 'package:vrapp/utils/toast_utils.dart';

class ConnectUtils {
  static ConnectUtils? _instace;
  static ConnectUtils? getInstace() {
    if (_instace == null) {
      _instace = ConnectUtils._();
    }
    return _instace;
  }

  //私有化构造方法
  ConnectUtils._();

  //通知
  //收到TCP消息回调 tcpReceiveData(收到的数据)
  var bus = EventBusUtil();

  //是否开启日志
  bool openLog = false;

  ///IP地址类型为ipv4
  bool addressTypeIpV4 = true;
  String wifiGateway = '';
  String wifiIP = '';
  int versionCode = 0;//头显版本号
  int contentRepoId = -1;//设备类型id
  ///进入app第一次连接
  bool firstConnect = true;

  //点击断开连接、记录状态，不再主动连接
  bool disconnectUDP = false; 

  /*
    UDP 
  */
  RawDatagramSocket? udpSocket;

  ///UDPSocket
  bool endUPDTimer = true;

  ///结束UDP定时器
  bool showUdpTimeOut = false;

  ///显示udp超时提示
  int udpTimeCount = 5;

  ///UDP 超时时间 5s
  Timer? _udpTimer;

  ///UDP定时器
  String udpErrorTip = '';

  ///UDP错误提示
  // int udpConnectNum = 0;

  bool connected = false;

  ///已连接
  VRIPInfoEntity? vrInfoEntity;

  ///服务端请求VRIP信息
  int gatewayFailNum = 0;

  String deviceName = '';

  ///UDPSocket
  bool checkConnect = false;

  ///上一次udp连接成功的port
  int lastPort = 0;

  Timer? _pingTimer;

  bool isPingRunning = false;

  int lastPongTime = 0;

  String get wifiIPHttp {
    String str = "http://$wifiIP:54321";
    return str;
  }

  ///计时器
  void startTimer() {
    if (!endUPDTimer && !checkConnect) return;
    if(openLog){
      print('ConnectUtils  startTimer endUPDTimer:$endUPDTimer checkConnect:$checkConnect');
    }

    endUPDTimer = false;
    udpTimeCount = 1;

    try {
      if(_udpTimer != null && _udpTimer!.isActive){
        _udpTimer?.cancel();
        if(openLog){
          print('ConnectUtils  old cancel');
        }
      }
    }catch(e){
      print(e);
    }

    _udpTimer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      if (udpTimeCount <= 0) {
        if(openLog){
          print('ConnectUtils   showUdpTimeOut：$showUdpTimeOut connected: $connected' );
        }
        if (showUdpTimeOut && !connected) {
          //没找到设备，请重新连接
          udpErrorTip = udpErrorTip.length > 0 ? udpErrorTip : '没找到设备，请重新连接';
          /* UDP连接通知
            state 状态 succ成功 fail失败 ；
            tip 错误提示
            data 返回内容
          */
          if(openLog){
            print('ConnectUtils  fail1');
          }
          bus.send('UDPConnectNotif',
              {'state': 'fail', 'tip': udpErrorTip, 'data': Map()});
        }else if(checkConnect){
          checkConnect = false;
          connected = false;
          if(openLog){
            print('ConnectUtils  fail2');
          }
          bus.send('UDPConnectNotif',
              {'state': 'fail', 'tip': udpErrorTip, 'data': Map()});
        }
        cancelTimer();
        closeUDPContent(lastPort);
      } else {
        udpTimeCount--;
      }
    });
  }

  //停止定时器
  void cancelTimer() {
    if(openLog){
      print('ConnectUtils  cancelTimer');
    }
    if (openLog) {
      print('UDP超时，取消');
    }
    CustomLogTool.getInstace()!.uploadLog(data: 'UDP超时，取消');
    _udpTimer?.cancel();
  }

  ///关闭UDP连接
  ///port 端口号 -现在定义 5514
  closeUDPContent(
    int toPort,
  ) {
    if (openLog) {
      print('关闭UDP');
    }
    CustomLogTool.getInstace()!.uploadLog(data: '关闭UDP');
    Map<String, dynamic> map = new Map();
    Map<String, dynamic> msgMap = new Map();
    msgMap['cmd'] = 'close';
    map['msg'] = msgMap;
    String data = jsonEncode(map);
    ConnectUtils.getInstace()!.udpConnectAndSendData(
      params: data,
      // toPort: 5514,
      toPort: toPort,
    );
    udpSocket?.close();
    udpSocket = null;
    //清空wifi网段地址
    wifiGateway = '';
    connected = false;
    udpErrorTip = '没找到设备，请重新连接';
    bus.send('UDPConnectNotif',
        {'state': 'fail', 'tip': udpErrorTip, 'data': Map()});
    if (openLog) {
      print('ConnectUtils closeUDPContent');
    }
  }

  ///开启UDP连接
  //isBroadCast 是否广播
  //port 端口号  -现在定义 5514
  //params  传递参数
  startUDPConnect(
    bool isBroadCast,
    String params,
    int toPort,
    bool connect
  ) async {
    if(disconnectUDP){
      CustomLogTool.getInstace()!.uploadLog(
          data:
          'disconnectUDP return');
      return;
    }
    if(connect){
      endUPDTimer = true;
    }else{
      checkConnect = true;
    }
    //现在不使用外部传入，使用默认定义值
    params = udpParams();

    //获取wifi网段地址
    await getWifiGateway().then((value) {
      if (udpSocket == null) {
        if (openLog) {
          print('绑定UDP连接wifiGateway：$wifiGateway toPort:$toPort');
        }
        CustomLogTool.getInstace()!
            .uploadLog(data: '绑定UDP连接wifiGateway：$wifiGateway toPort:$toPort');

        RawDatagramSocket.bind(
                addressTypeIpV4
                    ? InternetAddress.anyIPv4
                    : InternetAddress.anyIPv6,
                toPort,
                reuseAddress: true,
                reusePort: true)
            .then((RawDatagramSocket socket) {
          socket.broadcastEnabled = isBroadCast; //开启广播
          udpSocket = socket;

          //监听UDP数据
          listenUDPContent(toPort);

          udpConnectAndSendData(
            params: params,
            toPort: toPort,
          );
        });
      } else {
        if (openLog) {
          print('开启UDP连接address： $wifiGateway port:${udpSocket?.port}');
        }
        CustomLogTool.getInstace()!.uploadLog(
            data: '开启UDP连接address： $wifiGateway port:${udpSocket?.port}');
        udpConnectAndSendData(
          params: params,
          toPort: toPort,
        );
      }
    });
  }

  ///UDP连接并发送数据
  udpConnectAndSendData({
    required String params, //发送参数
    required int toPort, //端口号
  }) {
    // udpConnectNum++;
    String ipAddress = '';
    //发送UDP，
    //1.如果有上次连接ip，先使用上次ip
    //2.如果没有，使用广播
    //3.如果广播发送2次都没找到设备
    //4.通过服务器获取相同账号下头显ip
    if (wifiIP.length > 0) {
      ipAddress = wifiIP;
      if (openLog) {
        print('UDP连接并发送数据（使用上次ip） address： $ipAddress port:${udpSocket?.port}');
      }
      CustomLogTool.getInstace()!.uploadLog(
          data:
              'UDP连接并发送数据（使用上次ip） address： $ipAddress port:${udpSocket?.port}');
      //同一个ip尝试3次以上，都失败，发送广播尝试
      // if (udpConnectNum >= 4) {
      //   wifiIP = '';
      //   udpConnectNum = 0;
      //   if (openLog) {
      //     print('同一个ip尝试3次以上，都失败，下次发送广播尝试');
      //   }
      //   CustomLogTool.getInstace()!.uploadLog(data: '同一个ip尝试3次以上，都失败，下次发送广播尝试');
      // }
      // } else if (udpConnectNum <= 1) {
      //   ipAddress = wifiGateway;
      //   if (openLog) {
      //     print('UDP连接并发送数据（使用广播ip） address： $ipAddress port:${udpSocket?.port}');
      //   }
      //   CustomLogTool.getInstace()!.uploadLog(
      //       data:
      //           'UDP连接并发送数据（使用广播ip） address： $ipAddress port:${udpSocket?.port}');
    } else {
      getVRIP().then((succ) {
        int state = 0;
        if (succ) {
          //接口拿到地址
          ipAddress = vrInfoEntity!.ipAddress;
          //覆盖之前保存的wifiIP
          wifiIP = ipAddress;
          state = 1;
        } else {
          //接口获取失败
          ipAddress = wifiGateway;
        }

        udpSendData(params: params, toPort: toPort, ipAddress: ipAddress);
        if (openLog) {
          print(
              'UDP连接并发送数据(接口发送：${state == 1 ? '接口IP' : '广播IP'}) address： $ipAddress port:${udpSocket?.port}');
        }
        CustomLogTool.getInstace()!.uploadLog(
            data:
                'UDP连接并发送数据(接口发送：${state == 1 ? '接口IP' : '广播IP'}) address： $ipAddress port:${udpSocket?.port}');
      });

      return;
    }

    udpSendData(params: params, toPort: toPort, ipAddress: ipAddress);
    if(params.contains('search_device') && wifiGateway.length > 0 && ipAddress != wifiGateway){
      udpSendData(params: params, toPort: toPort, ipAddress: wifiGateway);
    }
    if (openLog) {
      print('UDP连接并发送数据 address： $ipAddress port:${udpSocket?.port}');
    }
    CustomLogTool.getInstace()!.uploadLog(
        data: 'UDP连接并发送数据 address： $ipAddress port:${udpSocket?.port}');
  }

  //获取VRHOME IP地址
  Future<bool> getVRIP() async {
    if (!AccountUtil.isLogin) return false; //未登录不处理
    vrInfoEntity = new VRIPInfoEntity(); //重置
    Map<String, dynamic> map = new Map();
    Map<String, dynamic>? jsonMap = JsonUtils.getInstace()?.getJsonText(map);
    Map<String, dynamic> response =
        await HttpUtils.getInstace()!.post(BaseApi.Get_VRIP_API, jsonMap!);
    if (response['code'] == 200) {
      if (response['data'] == null) {
        return false;
      }
      VRIPInfoEntity entity = VRIPInfoEntity().fromJson(response['data']);
      vrInfoEntity = entity;
      return true;
    } else {
      return false;
    }
  }

  ///UDP发送数据
  udpSendData({
    required String params, //发送参数
    required int toPort, //端口号
    required String ipAddress, //IP地址
  }) {
    if(disconnectUDP){
      return;
    }
    if(params.contains('"cmd":"search_device"')){
      //开启定时器
      startTimer();
    }
    if (ipAddress.length <= 0) return;
    if (openLog) {
      print(
          'UDP发送数据------ipAddress:$ipAddress toPort :$toPort params :$params');
    }
    CustomLogTool.getInstace()!.uploadLog(
        data:
            'UDP发送数据------ipAddress:$ipAddress toPort :$toPort params :$params');
    //AES加密
    params = AesUtils().aesEncrypt(params);
    udpSocket?.send(
      utf8.encode(params),
      InternetAddress(ipAddress),
      toPort,
    );
  }

  ///监听UDP连接
  ///port 端口号 -现在定义 5514
  listenUDPContent(int toPort) async {
    final info = NetworkInfo();
    String? getWifiIP = await info.getWifiIP();

    if (openLog) {
      print('UDP连接${udpSocket?.address.address}:${udpSocket?.port}');
    }
    if (udpSocket == null) {
      if (openLog) print('监听UDP连接失败：udpSocket 为null');
      CustomLogTool.getInstace()!.uploadLog(data: '监听UDP连接失败：udpSocket 为null');
    }
    CustomLogTool.getInstace()!.uploadLog(
        data: 'UDP连接${udpSocket?.address.address}:${udpSocket?.port}');
    udpSocket?.listen(
      (RawSocketEvent e) {
        if (openLog) {
          print('监听UDP状态---- $e');
        }
        CustomLogTool.getInstace()!.uploadLog(data: '监听UDP状态---- $e');
        if (e == RawSocketEvent.closed) {
          return;
        }

        Datagram? d = udpSocket?.receive();
        if (d == null) return;
        if (openLog) {
          print('收到数据UDP连接---- ${d.address.address}:${d.port}');
        }
        CustomLogTool.getInstace()!
            .uploadLog(data: '收到数据UDP连接---- ${d.address.address}:${d.port}');
        gatewayFailNum = 0; //网关连通，失败次数重置
        //过滤自己
        if (d.address.address == getWifiIP) return;

        String udpReceiveData = utf8.decode(d.data);
        if('pong' == udpReceiveData){
          lastPongTime = DateTime.now().millisecondsSinceEpoch;
          return;
        }
        //AES解密
        udpReceiveData = AesUtils().decryptAes(udpReceiveData);
        if (openLog) {
          print('收到数据UDP连接Datagram from ${d.address.address}:${d.port}' +
              udpReceiveData);
        }
        CustomLogTool.getInstace()!.uploadLog(
            data: '收到数据UDP连接Datagram from ${d.address.address}:${d.port}' +
                udpReceiveData);

        //收到UDP消息回调 receiveData(收到的数据)
        bus.send('UDPReceiveNotif', udpReceiveData);

        //将JSON字符串转为map
        Map<String, dynamic> map = json.decode(udpReceiveData);
        Map<String, dynamic> msgMap = map['msg'];
        Map<String, dynamic> comMap = map['com'] ?? {};
        //过滤app端互相发送广播
        if (comMap.keys.length > 0 && comMap['from'] == 'client') {
          if (openLog) {
            print('收到数据UDP连接-过滤client之间广播');
          }
          CustomLogTool.getInstace()!.uploadLog(data: '收到数据UDP连接-过滤client之间广播');
          return;
        }
        if (msgMap.containsKey("version")) {
          versionCode = msgMap['version'];
        }
        if (msgMap.containsKey("contentRepoId")) {
          contentRepoId = msgMap['contentRepoId'];
        }
        if (msgMap['code'] == 1) {
          //1成功 2未登录 3账号不一致
          if(msgMap['cmd'] == 'search_device'){
            // udpConnectNum = 0;
            wifiIP = d.address.address;
            connected = true;
            bus.send(
                'UDPConnectNotif', {'state': 'succ', 'tip': '', 'data': msgMap});
            deviceName = msgMap['device'] ?? '';
            if(openLog){
              print('ConnectUtils  succ');
            }
            cancelTimer(); //收到UDP消息，关闭定时器
            lastPort = toPort;
            if(!isPingRunning){
              startPingTimer();
            }
          }
        } else if (msgMap['code'] == 2) {
          //没找到设备，请重新连接
          udpErrorTip = '头显未登录';
        } else if (msgMap['code'] == 3) {
          //没找到设备，请重新连接
          udpErrorTip = '账号不一致';
        } else {
          //没找到设备，请重新连接
          udpErrorTip = '未知错误';
        }
      },
      onError: (err) {
        if (openLog) {
          print('UDP连接报错---$err');
        }
        CustomLogTool.getInstace()!
            .uploadLog(data: 'UDP连接报错---$err gatewayFailNum：$gatewayFailNum');
        SocketException exception = err;
        if (exception.osError?.errorCode == 65) {
          //避免多次、错误提示；
          gatewayFailNum++;
          if (gatewayFailNum >= 3) {
            gatewayFailNum = 0;
            ToastUtils.myToast(
                '请检测您本地网关的连通性,您可以在 `设置-->隐私-->本地网络`界面修改 app 的权限设置');
          }
        }else{
          // closeUDPContent(toPort);
          udpSocket?.close();
          udpSocket = null;
          connected = false;
        }
        // udpSocket = null;
        // ConnectUtils.getInstace()!.startUDPConnect(true, '', 5514, true);
      },
    );
  }

  void startPingTimer(){
    print('startPingTimer==========================');
    if(udpSocket == null){
      return;
    }
    isPingRunning = true;
    lastPongTime = DateTime.now().millisecondsSinceEpoch;
    _pingTimer = Timer.periodic(Duration(seconds: 3), (Timer timer) {
      try{
        if(DateTime.now().millisecondsSinceEpoch - lastPongTime > 15000){
          stopPingTimer();
          return;
        }
        udpSocket?.send(
          utf8.encode('ping'),
          InternetAddress(wifiIP),
          5514,
        );
      }catch(e){
        stopPingTimer();
      }
    });
  }

  void stopPingTimer(){
    try {
      if(_pingTimer!.isActive){
        _pingTimer?.cancel();
        isPingRunning = false;
        if(openLog){
          print('pingTimer cancel');
        }
      }
    }catch(e){
      print(e);
    }
  }

//------------------------------------------------------------------------------
  ///获取局域网段地址
  // ignore: body_might_complete_normally_nullable
  Future<String?> getWifiGateway() async {

    final info = NetworkInfo();
    String? getWifiIP = await info.getWifiIP();
    if (getWifiIP == null) {

      //判断热点地址是否有值
      MethodChannel _channel = const MethodChannel('com.yuhe.vrapp.scrcpy');
      //获取热点地址
      String getApIp = await _channel.invokeMethod('apIp');

      if(getApIp.toString().isEmpty){//没有热点地址
            if(openLog){
              print('UDP连接-- 没有热点地址');
            }
           Future.delayed(Duration(seconds: 1), () {
           bus.send('UDPConnectNotif',{'state': 'fail', 'tip': '请检查您的Wi-Fi', 'data': Map()});
          });
          return '';
      }else{//有热点地址
        List<String> addressList = getApIp.toString().split(".");
        String gateway = '';
        for (var i = 0; i < addressList.length; i++) {
          if (i >= addressList.length - 1) {
            gateway += '255';

            wifiGateway = gateway;
            if(openLog){
              print('UDP连接-- 有热点地址:$gateway');
            }
            return gateway;
          }
          gateway += addressList[i] + '.';
        }
      }

      if(openLog){
        print('UDP连接-- 没有Wifi地址');
      }
      Future.delayed(Duration(seconds: 1), () {
        bus.send('UDPConnectNotif',
            {'state': 'fail', 'tip': '请检查您的Wi-Fi', 'data': Map()});
      });
      return '';
    }

    List<String> addressList = getWifiIP.split(".");
    String gateway = '';
    for (var i = 0; i < addressList.length; i++) {
      if (i >= addressList.length - 1) {
        gateway += '255';

        wifiGateway = gateway;
        if(openLog){
          print('UDP连接-- 有Wifi地址:$gateway');
        }
        return gateway;
      }
      gateway += addressList[i] + '.';
    }
  }

  //配置TCP发送命令参数
  String sendTCPParams(String cmd) {
    String params = '';
    Map map = new Map();
    map = {
      'msg': {
        'code': 0, //成功
        'result': '', //返回结果
        'cmd': cmd, //命令名称
        'thePort': '', //端口号-用于TCP连接
        'user_id': AccountUtil.localUID, //用户id
      },
      'com': commentParams(), //公参数
      'ext': {},
    };
    params = json.encode(map);
    return params;
  }

  //配置UDP参数
  String udpParams() {
    String params = '';
    Map map = new Map();
    map = {
      'msg': {
        'code': 0, //成功
        'result': '', //返回结果
        'cmd': 'search_device', //命令名称
        'thePort': '', //端口号-用于TCP连接
        'user_id': AccountUtil.localUID, //用户id
      },
      'com': commentParams(), //公参数
      'ext': {},
    };
    params = json.encode(map);
    // //AES加密
    // params = AesUtils().aesEncrypt(params);
    return params;
  }

  //配置公参数
  Map commentParams() {
    Map map = new Map();
    map = {
      'channleId': Platform.isIOS ? 'iOS' : 'android', //渠道编号 -iOS android
      'versionId': Constants.deviceInfo["version"], //版本号
      'deviceid': Constants.deviceInfo["deviceId"], //设备编号
      'from': 'client' //server client
    };
    return map;
  }
}
