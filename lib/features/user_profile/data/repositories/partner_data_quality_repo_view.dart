/// Read-only surface needed by [PartnerContextResolver] to know whether a
/// partner has an unresolved data-quality flag. Real repository (built in
/// Phase 3 Task 10) implements this; tests provide an in-memory stub.
abstract class PartnerDataQualityRepoView {
  bool isFlaggedUnresolved(String partnerId);
}
