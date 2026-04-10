@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Loan Participant - Base View'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
  serviceQuality: #X,
  sizeCategory: #S,
  dataClass: #MIXED
}
define view entity ZR_LOAN_PARTICIPANT_U
  as select from zloan_part_u
  /* CRITICAL FIX: Add 'to parent' here */
  association to parent ZR_LoanHeader_U as _Header on $projection.LoanId = _Header.LoanId
{
  key part_id      as PartId,
      loan_id      as LoanId,
      role         as Role,
      full_name    as FullName,
      credit_score as CreditScore,
  
      case 
        when credit_score > 750 then 'Excellent'
        when credit_score > 650 then 'Good'
        else 'Review Required'
      end as CreditRating,

      /* Exposed association */
      _Header 
}
