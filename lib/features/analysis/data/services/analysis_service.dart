/// analyze-chat 傳輸層統一入口（歷史 import 路徑）。
///
/// 實體：typed 輔助 client（OCR／潤飾／微調）在
/// `analysis_auxiliary_client.dart`；主分析串流在
/// `analyze_stream_client.dart`；共用錯誤與 payload 模型在
/// `analysis_exceptions.dart` 與 `analysis_transport_support.dart`。
library;

export 'analysis_auxiliary_client.dart';
export 'analysis_exceptions.dart';
export 'analysis_transport_support.dart' show OverchargeConfirmationPayload;
export 'analyze_stream_client.dart'
    show
        AnalysisStreamContent,
        AnalysisStreamContentKind,
        AnalysisStreamUpdate,
        AnalysisStreamUpdateKind;
