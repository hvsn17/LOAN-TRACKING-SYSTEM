CLASS lhc_Loan DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PUBLIC SECTION.
    TYPES: tt_loan_buffer TYPE TABLE OF zloan_hdr_u.
    TYPES: tt_part_buffer TYPE TABLE OF zloan_part_u.
    CLASS-DATA: gt_loan_buffer   TYPE tt_loan_buffer.
    CLASS-DATA: gt_deleted_keys  TYPE TABLE OF zloan_hdr_u.
    CLASS-DATA: gt_deleted_parts TYPE TABLE OF zloan_part_u.
    CLASS-DATA: gt_new_parts TYPE TABLE OF zloan_part_u.
    CLASS-DATA: gt_part_buffer TYPE tt_part_buffer. " Add this buffer

  PRIVATE SECTION.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Loan RESULT result.
    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Loan RESULT result.
    METHODS create FOR MODIFY
      IMPORTING entities FOR CREATE Loan.
    METHODS update FOR MODIFY
      IMPORTING entities FOR UPDATE Loan.
    METHODS delete FOR MODIFY
      IMPORTING keys FOR DELETE Loan.
    METHODS read FOR READ
      IMPORTING keys FOR READ Loan RESULT result.
    METHODS lock FOR LOCK
      IMPORTING keys FOR LOCK Loan.
    METHODS rba_Items FOR READ
      IMPORTING keys_rba FOR READ Loan\_Items FULL result_requested RESULT result LINK association_links.
    METHODS cba_Items FOR MODIFY
      IMPORTING entities_cba FOR CREATE Loan\_Items.
    METHODS approveLoan FOR MODIFY
      IMPORTING keys FOR ACTION Loan~approveLoan RESULT result.
ENDCLASS.

CLASS lhc_Loan IMPLEMENTATION.

  METHOD get_instance_features.
    READ ENTITIES OF ZR_LoanHeader_U IN LOCAL MODE
      ENTITY Loan FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_loans).

    result = VALUE #( FOR ls_loan IN lt_loans
      ( %tky = ls_loan-%tky
        %action-approveLoan = COND #( WHEN ls_loan-Status = 'A'
                                      THEN if_abap_behv=>fc-o-disabled
                                      ELSE if_abap_behv=>fc-o-enabled ) ) ).
  ENDMETHOD.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD create.
    LOOP AT entities INTO DATA(ls_entity).
      DATA(ls_new_loan) = CORRESPONDING zloan_hdr_u( ls_entity MAPPING FROM ENTITY ).
      ls_new_loan-status = 'N'.
      INSERT ls_new_loan INTO TABLE gt_loan_buffer.
    ENDLOOP.
  ENDMETHOD.

  METHOD update.
    LOOP AT entities INTO DATA(ls_entity).
      READ TABLE gt_loan_buffer WITH KEY loan_id = ls_entity-LoanId
                                ASSIGNING FIELD-SYMBOL(<fs_buf>).
      IF sy-subrc <> 0.
        SELECT SINGLE * FROM zloan_hdr_u
          WHERE loan_id = @ls_entity-LoanId
          INTO @DATA(ls_db).
        INSERT ls_db INTO TABLE gt_loan_buffer ASSIGNING <fs_buf>.
      ENDIF.
      <fs_buf> = CORRESPONDING #( BASE ( <fs_buf> ) ls_entity MAPPING FROM ENTITY ).
    ENDLOOP.
  ENDMETHOD.

  METHOD delete.
    LOOP AT keys INTO DATA(ls_key).
      DELETE gt_loan_buffer WHERE loan_id = ls_key-LoanId.
      APPEND VALUE #( loan_id = ls_key-LoanId ) TO gt_deleted_keys.
    ENDLOOP.
  ENDMETHOD.

  METHOD read.
    LOOP AT keys INTO DATA(ls_key).
      READ TABLE gt_loan_buffer WITH KEY loan_id = ls_key-LoanId
                                INTO DATA(ls_loan).
      IF sy-subrc <> 0.
        SELECT SINGLE * FROM zloan_hdr_u
          WHERE loan_id = @ls_key-LoanId
          INTO @ls_loan.
        IF sy-subrc <> 0.
          APPEND VALUE #(
            %tky        = ls_key-%tky
            %fail-cause = if_abap_behv=>cause-not_found
          ) TO failed-loan.
          CONTINUE.
        ENDIF.
      ENDIF.

      APPEND VALUE #(
        %tky          = ls_key-%tky
        LoanId        = ls_loan-loan_id
        LoanType      = ls_loan-loan_type
        Amount        = ls_loan-amount
        Currency      = ls_loan-currency
        Status        = ls_loan-status
        CreatedBy     = ls_loan-created_by
        LastChangedAt = ls_loan-last_changed_at
      ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD lock.
  ENDMETHOD.

  METHOD rba_Items.
    " 1. Loop through the requested Headers (Loans)
    LOOP AT keys_rba ASSIGNING FIELD-SYMBOL(<ls_key>).

      " 2. Find participants in the Buffer (New entries not yet in DB)
      LOOP AT gt_part_buffer INTO DATA(ls_buf_part) WHERE loan_id = <ls_key>-LoanId.
        APPEND VALUE #(
          source-%tky = <ls_key>-%tky
          target-PartId = ls_buf_part-part_id
        ) TO association_links.
      ENDLOOP.

      " 3. Find participants in the Database (Already saved entries)
      SELECT part_id FROM zloan_part_u
        WHERE loan_id = @<ls_key>-LoanId
        INTO TABLE @DATA(lt_db_parts).

      LOOP AT lt_db_parts INTO DATA(ls_db_part).
        " Avoid adding duplicates if it's already in the buffer
        IF NOT line_exists( association_links[ target-PartId = ls_db_part-part_id ] ).
          APPEND VALUE #(
            source-%tky = <ls_key>-%tky
            target-PartId = ls_db_part-part_id
          ) TO association_links.
        ENDIF.
      ENDLOOP.

    ENDLOOP.

    " 4. Fill result if the framework wants the actual data records
    IF result_requested = abap_true.
      " If needed, you can select * from zloan_part_u here to fill 'result'
    ENDIF.
  ENDMETHOD.
METHOD cba_Items.
    LOOP AT entities_cba INTO DATA(ls_entity).
      LOOP AT ls_entity-%target INTO DATA(ls_target).

        " 1. Generate the unique ID
        DATA(lv_part_id) = cl_system_uuid=>create_uuid_x16_static( ).

        " 2. Append to the Participant buffer (now inside lhc_loan)
        APPEND VALUE zloan_part_u(
          part_id      = lv_part_id
          loan_id      = ls_entity-LoanId
          role         = ls_target-Role
          full_name    = ls_target-FullName
          credit_score = ls_target-CreditScore
        ) TO gt_part_buffer. " No lhc_participant prefix needed now

        " 3. Map the temporary CID to the new ID
        APPEND VALUE #( %cid   = ls_target-%cid
                        PartId = lv_part_id ) TO mapped-participant.

      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD approveLoan.
    LOOP AT keys INTO DATA(ls_key).
      READ TABLE gt_loan_buffer WITH KEY loan_id = ls_key-LoanId
                                ASSIGNING FIELD-SYMBOL(<fs_loan>).

      IF sy-subrc <> 0.
        SELECT SINGLE * FROM zloan_hdr_u
          WHERE loan_id = @ls_key-LoanId
          INTO @DATA(ls_db_loan).

        IF sy-subrc <> 0.
          APPEND VALUE #(
            %tky        = ls_key-%tky
            %fail-cause = if_abap_behv=>cause-not_found
          ) TO failed-loan.
          CONTINUE.
        ENDIF.
        INSERT ls_db_loan INTO TABLE gt_loan_buffer ASSIGNING <fs_loan>.
      ENDIF.

      <fs_loan>-status = 'A'.

      APPEND VALUE #(
        %tky                 = ls_key-%tky
        %param-LoanId        = <fs_loan>-loan_id
        %param-LoanType      = <fs_loan>-loan_type
        %param-Amount        = <fs_loan>-amount
        %param-Currency      = <fs_loan>-currency
        %param-Status        = <fs_loan>-status
        %param-CreatedBy     = <fs_loan>-created_by
        %param-LastChangedAt = <fs_loan>-last_changed_at
      ) TO result.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.




"=======================================================

CLASS lhc_Participant DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PUBLIC SECTION.
    TYPES: tt_part_buffer TYPE TABLE OF zloan_part_u.
    CLASS-DATA: gt_part_buffer TYPE tt_part_buffer.

  PRIVATE SECTION.
    METHODS update FOR MODIFY
      IMPORTING entities FOR UPDATE Participant.
    METHODS delete FOR MODIFY
      IMPORTING keys FOR DELETE Participant.
    METHODS read FOR READ
      IMPORTING keys FOR READ Participant RESULT result.
    METHODS rba_Header FOR READ
      IMPORTING keys_rba FOR READ Participant\_Header FULL result_requested RESULT result LINK association_links.
ENDCLASS.

CLASS lhc_Participant IMPLEMENTATION.

  METHOD update.
    LOOP AT entities INTO DATA(ls_entity).
      READ TABLE gt_part_buffer WITH KEY part_id = ls_entity-PartId
                                ASSIGNING FIELD-SYMBOL(<fs_part>).
      IF sy-subrc <> 0.
        SELECT SINGLE * FROM zloan_part_u
          WHERE part_id = @ls_entity-PartId
          INTO @DATA(ls_db_part).
        INSERT ls_db_part INTO TABLE gt_part_buffer ASSIGNING <fs_part>.
      ENDIF.
      <fs_part> = CORRESPONDING #( BASE ( <fs_part> ) ls_entity MAPPING FROM ENTITY ).
    ENDLOOP.
  ENDMETHOD.

  METHOD delete.
    LOOP AT keys INTO DATA(ls_key).
      DELETE gt_part_buffer WHERE part_id = ls_key-PartId.
      APPEND VALUE #( part_id = ls_key-PartId ) TO lhc_Loan=>gt_deleted_parts.
    ENDLOOP.
  ENDMETHOD.

  METHOD read.
    LOOP AT keys INTO DATA(ls_key).
      READ TABLE gt_part_buffer WITH KEY part_id = ls_key-PartId
                                INTO DATA(ls_part).
      IF sy-subrc <> 0.
        SELECT SINGLE * FROM zloan_part_u
          WHERE part_id = @ls_key-PartId
          INTO @ls_part.

        IF sy-subrc <> 0.
          APPEND VALUE #(
            %tky        = ls_key-%tky
            %fail-cause = if_abap_behv=>cause-not_found
          ) TO failed-participant.
          CONTINUE.
        ENDIF.
      ENDIF.

      APPEND VALUE #(
        %tky        = ls_key-%tky
        PartId      = ls_part-part_id
        LoanId      = ls_part-loan_id
        Role        = ls_part-role
        FullName    = ls_part-full_name
        CreditScore = ls_part-credit_score
      ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD rba_Header.
    " This method allows the Participant to navigate back to the Loan Header
    LOOP AT keys_rba INTO DATA(ls_key).
      SELECT SINGLE loan_id FROM zloan_part_u
        WHERE part_id = @ls_key-PartId
        INTO @DATA(lv_loan_id).

      IF sy-subrc = 0.
        APPEND VALUE #(
          source-%tky = ls_key-%tky
          target-LoanId = lv_loan_id
        ) TO association_links.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

"=======================================================

CLASS lsc_ZR_LOANHEADER_U DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS finalize          REDEFINITION.
    METHODS check_before_save REDEFINITION.
    METHODS save              REDEFINITION.
    METHODS cleanup           REDEFINITION.
    METHODS cleanup_finalize  REDEFINITION.
ENDCLASS.

CLASS lsc_ZR_LOANHEADER_U IMPLEMENTATION.

  METHOD finalize.
  ENDMETHOD.

  METHOD check_before_save.
  ENDMETHOD.

  METHOD save.
  " ---- 1. DELETE LOANS ----
  LOOP AT lhc_Loan=>gt_deleted_keys INTO DATA(ls_del_loan).
    DELETE FROM zloan_hdr_u WHERE loan_id = @ls_del_loan-loan_id.
  ENDLOOP.

  " ---- 2. DELETE PARTICIPANTS ----
  LOOP AT lhc_Loan=>gt_deleted_parts INTO DATA(ls_del_part).
    DELETE FROM zloan_part_u WHERE part_id = @ls_del_part-part_id.
  ENDLOOP.

  " ---- 3. CREATE/UPDATE LOANS ----
  LOOP AT lhc_Loan=>gt_loan_buffer INTO DATA(ls_loan).
    MODIFY zloan_hdr_u FROM @ls_loan.
  ENDLOOP.

  " ---- 4. MOVE PARTICIPANTS FROM DRAFT TO ACTIVE ----
LOOP AT lhc_Loan=>gt_part_buffer INTO DATA(ls_part).
    MODIFY zloan_part_u FROM @ls_part.
  ENDLOOP.
ENDMETHOD.

  METHOD cleanup.
    CLEAR lhc_Loan=>gt_loan_buffer.
    CLEAR lhc_Loan=>gt_deleted_keys.
    CLEAR lhc_Loan=>gt_deleted_parts.
    CLEAR lhc_Participant=>gt_part_buffer.
  ENDMETHOD.

  METHOD cleanup_finalize.
  ENDMETHOD.

ENDCLASS.
