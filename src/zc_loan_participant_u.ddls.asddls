@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Loan Participant - Projection'
@Metadata.ignorePropagatedAnnotations: true

@Metadata.allowExtensions: true
define view entity ZC_LOAN_PARTICIPANT_U 
  as projection on ZR_LOAN_PARTICIPANT_U
{
    key PartId,
    LoanId,
    Role,
    FullName,
    CreditScore,
    CreditRating,
    
    /* CRITICAL: Must match the name 'ZC_LOANHEADER_U' exactly */
    _Header : redirected to parent ZC_LOANHDR_U 
}
