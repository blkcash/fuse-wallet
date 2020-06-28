import 'package:ethereum_address/ethereum_address.dart';
import 'package:digitalrand/constans/exchangable_tokens.dart';
import 'package:digitalrand/models/jobs/base.dart';
import 'package:digitalrand/models/pro/pro_wallet_state.dart';
import 'package:digitalrand/models/pro/token.dart';
import 'package:digitalrand/models/transactions/transfer.dart';
import 'package:digitalrand/redux/actions/cash_wallet_actions.dart';
import 'package:digitalrand/redux/actions/pro_mode_wallet_actions.dart';
import 'package:digitalrand/redux/state/store.dart';
import 'package:digitalrand/services.dart';
import 'package:digitalrand/utils/addresses.dart';
import 'package:json_annotation/json_annotation.dart';

part 'swap_token_job.g.dart';

@JsonSerializable(explicitToJson: true, createToJson: false)
class SwapTokenJob extends Job {
  SwapTokenJob(
      {id,
      jobType,
      name,
      status,
      data,
      arguments,
      lastFinishedAt,
      timeStart,
      isReported,
      isFunderJob})
      : super(
            id: id,
            jobType: jobType,
            name: name,
            status: status,
            data: data,
            arguments: arguments,
            lastFinishedAt: lastFinishedAt,
            isReported: isReported,
            timeStart: timeStart ?? new DateTime.now().millisecondsSinceEpoch,
            isFunderJob: isFunderJob);

  bool isPending() => this.status == 'PENDING';
  bool isFailed() => this.status == 'FAILED';
  bool isConfirmed() => this.status == 'DONE';

  @override
  fetch() async {
    return api.getJob(this.id);
  }

  @override
  onDone(store, dynamic fetchedData) async {
    final logger = await AppFactory().getLogger('Job');
    logger.info('perform SwapTokenJob - $id');
    if (isReported == true) {
      this.status = 'FAILED';
      logger.info('SwapTokenJob FAILED');
      store.dispatch(segmentTrackCall('Wallet: SwapTokenJob FAILED'));
      return;
    }
    Job job = JobFactory.create(fetchedData);
    int current = DateTime.now().millisecondsSinceEpoch;
    int jobTime = this.timeStart;
    final int millisecondsIntoMin = 2 * 60 * 1000;
    if ((current - jobTime) > millisecondsIntoMin &&
        isReported != null &&
        !isReported) {
      store.dispatch(segmentTrackCall('Wallet: pending job',
          properties: new Map<String, dynamic>.from({'id': id, 'name': name})));
      this.isReported = true;
    }

    if (fetchedData['failReason'] != null && fetchedData['failedAt'] != null) {
      logger.info('SwapTokenJob FAILED');
        this.status = 'FAILED';
        String failReason = fetchedData['failReason'];
        this.status = 'FAILED';
        store.dispatch(proTransactionFailed(
            arguments['tokenAddress'], arguments['transfer']));
        store.dispatch(segmentTrackCall('Wallet: job failed',
            properties: new Map<String, dynamic>.from(
                {'id': id, 'failReason': failReason, 'name': name})));
        return;
    }

    if (job.lastFinishedAt == null || job.lastFinishedAt.isEmpty) {
      logger.info('SwapTokenJob not done');
      return;
    }

    if (fetchedData['data']['nextRealyJobId'] != null) {
      String nextRealyJobId = fetchedData['data']['nextRealyJobId'];
      logger.info('SwapTokenJob - nextRealyJobId - $nextRealyJobId');
      dynamic nextRealyJobResponse = await api.getJob(nextRealyJobId);

      if (nextRealyJobResponse['failReason'] != null && nextRealyJobResponse['failedAt'] != null) {
        logger.info('SwapTokenJob FAILED');
        this.status = 'FAILED';
        String failReason = nextRealyJobResponse['failReason'];
        this.status = 'FAILED';
        store.dispatch(proTransactionFailed(
            arguments['tokenAddress'], arguments['transfer']));
        store.dispatch(segmentTrackCall('Wallet: job failed',
            properties: new Map<String, dynamic>.from(
                {'id': id, 'failReason': failReason, 'name': name})));
        return;
      }

      if (nextRealyJobResponse['lastFinishedAt'] == null || nextRealyJobResponse['lastFinishedAt'].isEmpty) {
        logger.info('SwapTokenJob not done');
        return;
      }

      this.status = 'DONE';
      String txHash = nextRealyJobResponse['data']['txHash'];
      store.dispatch(sendErc20TokenSuccessCall(
          txHash, arguments['fromToken'].address, arguments['transfer']));
      ProWalletState proWalletState = store.state.proWalletState;
      String tokenAddress = arguments['toToken'].address.toLowerCase();
      if (tokenAddress != zeroAddress.toLowerCase()) {
        Token newToken = proWalletState.erc20Tokens[tokenAddress] ??
            exchangableTokens[checksumEthereumAddress(tokenAddress)];
        Map<String, Token> erc20Tokens = proWalletState.erc20Tokens
          ..putIfAbsent(
              tokenAddress,
              () => arguments['toToken'].copyWith(
                    address: newToken?.address?.toLowerCase(),
                    name: newToken?.name,
                    decimals: newToken?.decimals,
                    symbol: newToken?.symbol,
                    transactions: newToken.transactions.copyWith(
                        list: newToken.transactions.list..add(
                          arguments['transferIn'].copyWith(status: 'CONFIRMED', txHash: txHash))),
                  ));
        store.dispatch(new GetTokenListSuccess(erc20Tokens: erc20Tokens));
      }
      store.dispatch(ProJobDone(job: this, tokenAddress: arguments['fromToken'].address));
      store.dispatch(segmentTrackCall('Wallet: job succeeded',
          properties: new Map<String, dynamic>.from({'id': id, 'name': name})));
      return;
    }
  }

  @override
  dynamic argumentsToJson() => {
        'fromToken': arguments['fromToken'].toJson(),
        'toToken': arguments['toToken'].toJson(),
        'transfer': arguments['transfer'].toJson(),
        'transferIn': arguments['transferIn'].toJson()
      };

  @override
  Map<String, dynamic> argumentsFromJson(arguments) {
    if (arguments == null) {
      return arguments;
    }
    if (arguments.containsKey('fromToken')) {
      if (arguments['fromToken'] is Map && arguments['toToken'] is Map) {
        Map<String, dynamic> nArgs = Map<String, dynamic>.from(arguments);
        nArgs['toToken'] = Token.fromJson(arguments['toToken']);
        nArgs['fromToken'] = Token.fromJson(arguments['fromToken']);
        nArgs['transfer'] = Transfer.fromJson(arguments['transfer']);
        nArgs['transferIn'] = Transfer.fromJson(arguments['transferIn']);
        return nArgs;
      }
    }
    return arguments;
  }

  factory SwapTokenJob.fromJson(Map<String, dynamic> json) =>
      _$SwapTokenJobFromJson(json);
}
