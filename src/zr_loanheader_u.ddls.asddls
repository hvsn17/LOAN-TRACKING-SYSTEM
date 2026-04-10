@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'LOAN HEADER'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZR_LoanHeader_U as select from zloan_hdr_u
composition [0..*] of ZR_LOAN_PARTICIPANT_U as _Items
{
    key loan_id        as LoanId,
    loan_type          as LoanType,
    @Semantics.amount.currencyCode: 'Currency'
    amount             as Amount,
    currency           as Currency,
    status             as Status,
    created_by         as CreatedBy,
    last_changed_at    as LastChangedAt,
    
    _Items
}
