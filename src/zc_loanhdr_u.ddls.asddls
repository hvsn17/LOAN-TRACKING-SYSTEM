@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Loan Header - Projection'
@Metadata.allowExtensions: true

define root view entity ZC_LOANHDR_U
  provider contract transactional_query
  as projection on ZR_LoanHeader_U
{
    key LoanId,
    LoanType,
    Amount,
    Currency,
    Status,
    CreatedBy,
    LastChangedAt,
    
    /* Redirect to the specific Participant Projection */
    _Items : redirected to composition child ZC_LOAN_PARTICIPANT_U 
}
